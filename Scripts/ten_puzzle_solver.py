# ten_puzzle_solver.py
# 0〜9 の数字を4つ選んだ全組み合わせ（715通り）について
# 四則演算 + 括弧で 10 を作れるか判定し、難易度を付与して JSON で出力する

from itertools import product, permutations, combinations_with_replacement
from fractions import Fraction
import json

OPS = ['+', '-', '*', '/']

def patterns(a, b, c, d):
    """5通りの括弧パターンで全演算子の組み合わせを試し、(値, 式文字列) のリストを返す"""
    results = []

    def safe_div(x, y):
        return None if y == 0 else x / y

    def apply(op, x, y):
        if op == '+': return x + y
        if op == '-': return x - y
        if op == '*': return x * y
        if op == '/': return safe_div(x, y)

    def fmt(v):
        """Fraction を整数表示に（1/1 → 1）"""
        return str(int(v)) if v.denominator == 1 else str(v)

    for o1 in OPS:
        for o2 in OPS:
            for o3 in OPS:
                fa, fb, fc, fd = fmt(a), fmt(b), fmt(c), fmt(d)

                # パターン1: ((a o1 b) o2 c) o3 d
                v1 = apply(o1, a, b)
                if v1 is not None:
                    v2 = apply(o2, v1, c)
                    if v2 is not None:
                        v3 = apply(o3, v2, d)
                        if v3 is not None:
                            results.append((v3, f"(({fa}{o1}{fb}){o2}{fc}){o3}{fd}"))

                # パターン2: (a o1 (b o2 c)) o3 d
                v1 = apply(o2, b, c)
                if v1 is not None:
                    v2 = apply(o1, a, v1)
                    if v2 is not None:
                        v3 = apply(o3, v2, d)
                        if v3 is not None:
                            results.append((v3, f"({fa}{o1}({fb}{o2}{fc})){o3}{fd}"))

                # パターン3: (a o1 b) o3 (c o2 d)
                v1 = apply(o1, a, b)
                v2 = apply(o2, c, d)
                if v1 is not None and v2 is not None:
                    v3 = apply(o3, v1, v2)
                    if v3 is not None:
                        results.append((v3, f"({fa}{o1}{fb}){o3}({fc}{o2}{fd})"))

                # パターン4: a o1 ((b o2 c) o3 d)
                v1 = apply(o2, b, c)
                if v1 is not None:
                    v2 = apply(o3, v1, d)
                    if v2 is not None:
                        v3 = apply(o1, a, v2)
                        if v3 is not None:
                            results.append((v3, f"{fa}{o1}(({fb}{o2}{fc}){o3}{fd})"))

                # パターン5: a o1 (b o2 (c o3 d))
                v1 = apply(o3, c, d)
                if v1 is not None:
                    v2 = apply(o2, b, v1)
                    if v2 is not None:
                        v3 = apply(o1, a, v2)
                        if v3 is not None:
                            results.append((v3, f"{fa}{o1}({fb}{o2}({fc}{o3}{fd}))"))

    return results


TARGET = Fraction(10)


def prettify(expr):
    """
    不要な括弧を除去して読みやすい式に変換する。
    例: ((1+2)+3)+4 → 1+2+3+4
        ((1+1)*3)+4 → (1+1)*3+4
    アルゴリズム: 再帰下降パーサーで AST を作り、
    演算子優先度ルールに基づいて括弧なしで再構築する。
    """
    prec = {'+': 1, '-': 1, '*': 2, '/': 2}

    def tokenize(s):
        tokens = []
        i = 0
        while i < len(s):
            if s[i].isdigit():
                j = i
                while j < len(s) and s[j].isdigit():
                    j += 1
                tokens.append(s[i:j])
                i = j
            else:
                tokens.append(s[i])
                i += 1
        return tokens

    tokens = tokenize(expr)
    pos = [0]

    def parse_expr():
        left, lop = parse_term()
        while pos[0] < len(tokens) and tokens[pos[0]] in ('+', '-'):
            op = tokens[pos[0]]; pos[0] += 1
            right, rop = parse_term()
            # 右辺が同じ優先度のとき、右辺に括弧が不要か判断
            left = (left, op, right, lop, rop)
            lop = op
        return left, lop

    def parse_term():
        left, lop = parse_factor()
        while pos[0] < len(tokens) and tokens[pos[0]] in ('*', '/'):
            op = tokens[pos[0]]; pos[0] += 1
            right, rop = parse_factor()
            left = (left, op, right, lop, rop)
            lop = op
        return left, lop

    def parse_factor():
        if tokens[pos[0]] == '(':
            pos[0] += 1
            node, op = parse_expr()
            pos[0] += 1  # ')'
            return node, op
        else:
            val = tokens[pos[0]]; pos[0] += 1
            return val, None

    def render(node, parent_op=None, is_right=False):
        if isinstance(node, str):
            return node
        left, op, right = node[0], node[1], node[2]
        ls = render(left, op, is_right=False)
        rs = render(right, op, is_right=True)

        # 左辺に括弧が必要か
        need_left = False
        if isinstance(left, tuple):
            child_op = left[1]
            if prec[child_op] < prec[op]:
                need_left = True

        # 右辺に括弧が必要か
        need_right = False
        if isinstance(right, tuple):
            child_op = right[1]
            if prec[child_op] < prec[op]:
                need_right = True
            elif prec[child_op] == prec[op] and op in ('-', '/'):
                # a - (b + c) や a / (b * c) は括弧必要
                need_right = True

        ls = f"({ls})" if need_left else ls
        rs = f"({rs})" if need_right else rs

        result = f"{ls}{op}{rs}"

        # 外側の括弧が必要か（親演算子との比較）
        if parent_op is not None and prec[op] < prec[parent_op]:
            return result  # 呼び出し元で括弧付与
        return result

    try:
        tree, _ = parse_expr()
        return render(tree)
    except Exception:
        return expr  # パース失敗時は元の式を返す


def display_expr(expr):
    """内部記号（*  /  -）を表示用記号（× ÷ −）に変換"""
    return expr.replace('*', '×').replace('/', '÷').replace('-', '−')


def solve(digits):
    """
    digits: sorted list of 4 ints
    returns: (solution_count, best_example_str or None)
    best_example = 最も文字数の短い解（不要な括弧が少ない）
    """
    fracs = [Fraction(d) for d in digits]
    solutions = set()
    best = None

    for perm in permutations(fracs):
        a, b, c, d = perm
        for val, expr in patterns(a, b, c, d):
            if val == TARGET:
                solutions.add(expr)
                # 括弧を除去して文字数を比較し、最短を選ぶ
                pretty = prettify(expr)
                if best is None or len(pretty) < len(best):
                    best = pretty

    return len(solutions), (display_expr(best) if best else None)


# 全715組み合わせを生成
all_combos = list(combinations_with_replacement(range(10), 4))
print(f"総組み合わせ数: {len(all_combos)}")

results = []
solvable = 0
impossible = 0

for digits in all_combos:
    count, example = solve(list(digits))

    if count > 0:
        solvable += 1
        if count >= 20:
            difficulty = "easy"
        elif count >= 5:
            difficulty = "normal"
        else:
            difficulty = "hard"
    else:
        impossible += 1
        difficulty = "impossible"

    results.append({
        "digits": list(digits),
        "solutionCount": count,
        "example": example,
        "difficulty": difficulty
    })

print(f"解あり: {solvable}, 解なし: {impossible}")

# JSON 出力
with open('/home/claude/ten_puzzle_problems.json', 'w', encoding='utf-8') as f:
    json.dump(results, f, ensure_ascii=False, indent=2)

print("✅ ten_puzzle_problems.json を出力しました")

# サンプル確認
print("\n--- サンプル（各難易度5件）---")
for diff in ["easy", "normal", "hard", "impossible"]:
    samples = [r for r in results if r["difficulty"] == diff][:4]
    print(f"\n[{diff}]")
    for s in samples:
        print(f"  {s['digits']} → {s['solutionCount']}解 | 例: {s['example']}")
