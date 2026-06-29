//
//  TenPuzzleModels.swift
//  FDL-TenBlitz
//
//  Created by 空飛ぶ研究室(FlyingDevLab) on 2026/06/13.
//

// 四則演算テンパズルで使うデータ型・問題データベース・式の評価器を定義するファイル。
// ロジックを持たない型定義（Models）と純粋関数（Validator）のみを置く。
// ViewModelはTenPuzzleViewModel.swiftに分離している。
//
// ★ このファイルの構成 ★
//   TenPuzzleProblem    … 1問分のデータ（数字・解数・ヒント・難易度）
//   TenPuzzleDifficulty … 難易度の4段階（easy / normal / hard / impossible）
//   TenPuzzleMode       … ゲームモード（modeA / modeB / modeC）
//   ExprToken           … 式を構成するトークン（数字・演算子・括弧）
//   TenPuzzleJudgment   … 式の判定結果（正解・不正解・構文エラーなど）
//   TenPuzzleDatabase   … JSONから問題を読み込むデータベース（遅延ロード）
//   TenPuzzleValidator  … トークン配列を評価して判定結果を返す
//   ExprParser          … 再帰下降法による四則演算パーサー

import SwiftUI

// MARK: - 問題データ

/// 四則演算テンパズルの1問分のデータ。
/// digits は昇順ソート済みの4つの数字（例: [1, 2, 6, 7]）。
/// solutionCount が0の問題が「作れない！」宣言の対象（impossibleモード）。
struct TenPuzzleProblem: Identifiable {
    let id             = UUID()
    let digits:        [Int]               // 昇順ソート済みの4桁（例: [1, 2, 6, 7]）
    let solutionCount: Int                // 解の個数（0 = 不可能問題）
    let example:       String?            // ヒント用の解の例（impossibleはnil）
    let difficulty:    TenPuzzleDifficulty
}

// MARK: - 難易度

/// 解の個数で決まる4段階の難易度。
/// easy/normal/hard は解ける問題、impossible は10を作れない問題。
enum TenPuzzleDifficulty: String, Codable {
    case easy       // かんたん：解が20個以上（403問）
    case normal     // ふつう：解が5〜19個（102問）
    case hard       // むずかしい：解が1〜4個（47問）
    case impossible // 作れない：解が0個（163問）
}

// MARK: - ゲームモード

/// プレイヤーが選ぶ3つのゲームモード。
/// モードAは解ける問題のみ、モードBはヒントあり、
/// モードCは難問と不可能問題が混在するチャレンジ。
enum TenPuzzleMode: String, CaseIterable {
    case modeA  // かんたん / ふつう問題のみ
    case modeB  // むずかしい問題のみ、ヒントあり
    case modeC  // チャレンジ：難問 + 不可能問題が混在

    var icon: String {
        switch self {
        case .modeA: return "⭐️"
        case .modeB: return "⭐️⭐️"
        case .modeC: return "⭐️⭐️⭐️"
        }
    }

    var title: String {
        switch self {
        case .modeA: return "かんたん / ふつう"
        case .modeB: return "むずかしい"
        case .modeC: return "チャレンジ"
        }
    }

    // ★ "description" は CustomStringConvertible が要求する名前と衝突するため
    //   "subtitle" を使う。衝突するとprint(mode)で予期せぬ挙動が起きる。
    var subtitle: String {
        switch self {
        case .modeA: return "10を作れる問題だけ。\nヒントを使いながら自分のペースで。"
        case .modeB: return "解が少ない難問。\nわからなければヒントを見よう。"
        case .modeC: return "難問 + 作れない問題が混在。\n「作れない！」と見破れたら正解。"
        }
    }

    var color: Color {
        switch self {
        case .modeA: return .green
        case .modeB: return .orange
        case .modeC: return .red
        }
    }

    /// 1セッションあたりの出題数
    static let problemsPerSession: Int = 10
}

// MARK: - 式トークン

/// ユーザーが組み立てる式の最小単位。
/// 数字タイル・演算子・括弧の3種類がある。
///
/// ★ slot とは？ ★
///   問題の4桁の数字には 0〜3 のスロット番号を振っている。
///   たとえば digits=[2,2,5,6] のとき、slot=0とslot=1はどちらも数字「2」だが
///   別のタイルを表す。slotで管理することで「2を2回使ってしまう」バグを防げる。
///
/// ★ Equatable を採用しない理由 ★
///   id が UUID のため自動合成すると「同じ型・同じ値でも別インスタンスは!=」になり
///   意図しない等値比較を招く。内部の型比較は ExprTokenType.Equatable のみで行う。
struct ExprToken: Identifiable {
    let id   = UUID()
    let type: ExprTokenType

    enum ExprTokenType: Equatable {
        case digit(value: Int, slot: Int)  // slot = 0〜3（4枚の数字タイルのどれか）
        case op(String)                    // "+" "−" "×" "÷"
        case paren(String)                 // "(" ")"
    }

    /// 画面に表示する文字列
    var displayText: String {
        switch type {
        case .digit(let v, _): return "\(v)"
        case .op(let s):       return s
        case .paren(let s):    return s
        }
    }

    /// 数字タイルなら true
    var isDigit: Bool {
        if case .digit = type { return true }
        return false
    }

    /// このトークンが使っているスロット番号（数字タイルでなければnil）
    var slot: Int? {
        if case .digit(_, let s) = type { return s }
        return nil
    }
}

// MARK: - 判定結果

/// 式を評価したときの4種類の結果。
/// Viewはこれをもとにフィードバックの色と文言を切り替える。
enum TenPuzzleJudgment: Equatable {
    case correct              // ✅ 式の値が10になった
    case wrongAnswer          // ❌ 式は正しいが10にならない
    case notAllDigitsUsed     // ⚠️ 4つの数字を全部使っていない
    case syntaxError          // ⚠️ 式が不完全または構文エラー

    /// フィードバック表示用の色
    var color: Color {
        self == .correct ? DS.gaugeFull : DS.gaugeWarn
    }

    /// フィードバック表示用のメッセージ
    var message: String {
        switch self {
        case .correct:          return "正解！"
        case .wrongAnswer:      return "ちがう…"
        case .notAllDigitsUsed: return "4つ全部使おう"
        case .syntaxError:      return "式が不完全だよ"
        }
    }
}

// MARK: - 問題データベース

/// JSONファイルから問題を読み込んで提供するデータベース。
/// 最初のアクセス時に1回だけ読み込み、以降はメモリにキャッシュする。
///
/// ★ enum（ケースなし）を名前空間として使う理由 ★
///   インスタンスを作れない「名前空間」として機能する。
///   静的メソッド・プロパティだけを持ち、
///   TenPuzzleDatabase() のようにインスタンス化できないことを型で表現している。
enum TenPuzzleDatabase {

    // ★ 遅延ロードパターン ★
    //   最初のアクセス時にJSONを読み込み、_all に保存する。
    //   2回目以降は保存済みの値をそのまま返すため、JSONの読み込みは1回だけ。
    //   メインスレッドでのみ呼ばれる前提のため排他制御は省略している。
    private static var _all: [TenPuzzleProblem]?

    static var all: [TenPuzzleProblem] {
        if let cached = _all { return cached }
        let loaded = loadFromJSON()
        _all = loaded
        return loaded
    }

    static var easyPool:       [TenPuzzleProblem] { all.filter { $0.difficulty == .easy       } }
    static var normalPool:     [TenPuzzleProblem] { all.filter { $0.difficulty == .normal     } }
    static var hardPool:       [TenPuzzleProblem] { all.filter { $0.difficulty == .hard       } }
    static var impossiblePool: [TenPuzzleProblem] { all.filter { $0.difficulty == .impossible } }

    /// モードに応じた出題プールをシャッフルして返す。
    /// モードCは難問と不可能問題を半々に混ぜる。
    static func pool(for mode: TenPuzzleMode) -> [TenPuzzleProblem] {
        switch mode {
        case .modeA:
            // かんたん(403問) + ふつう(102問)をシャッフル
            return (easyPool + normalPool).shuffled()
        case .modeB:
            // むずかしい(47問)のみ
            return hardPool.shuffled()
        case .modeC:
            // 難問 n/2 問 + 不可能問題 n/2 問をシャッフルして混ぜる
            let half  = TenPuzzleMode.problemsPerSession / 2
            let hard  = Array(hardPool.shuffled().prefix(half))
            let impos = Array(impossiblePool.shuffled().prefix(half))
            return (hard + impos).shuffled()
        }
    }

    // MARK: JSON読み込み

    /// Bundleの ten_puzzle_problems.json から問題を読み込む。
    /// ファイルが見つからない場合は空配列を返す（クラッシュしない安全設計）。
    private static func loadFromJSON() -> [TenPuzzleProblem] {
        guard let url  = Bundle.main.url(forResource: "ten_puzzle_problems", withExtension: "json"),
              let data = try? Data(contentsOf: url) else {
            return []
        }

        // JSON の構造に合わせた中間型
        struct RawProblem: Decodable {
            let digits:        [Int]
            let solutionCount: Int
            let example:       String?
            let difficulty:    TenPuzzleDifficulty
        }

        guard let raw = try? JSONDecoder().decode([RawProblem].self, from: data) else { return [] }

        return raw.map {
            TenPuzzleProblem(
                digits:        $0.digits,
                solutionCount: $0.solutionCount,
                example:       $0.example,
                difficulty:    $0.difficulty
            )
        }
    }
}

// MARK: - 式の判定器

/// トークン配列と問題の数字を受け取り、判定結果を返す純粋関数の集まり。
/// View・ViewModelはこの判定器を呼び出すだけで式の評価ができる。
enum TenPuzzleValidator {

    /// トークン配列を評価して TenPuzzleJudgment を返す。
    static func judge(tokens: [ExprToken], digits: [Int]) -> TenPuzzleJudgment {

        // ── 数字の使用チェック ──────────────────────────────────────
        // usedSlots = 式に含まれる digit トークンの slot 番号一覧
        let usedSlots = tokens.compactMap { $0.slot }

        // 全スロット（0〜3）が1回ずつ使われているか確認する
        let required = Set(0..<digits.count)
        guard Set(usedSlots) == required, usedSlots.count == digits.count else {
            return .notAllDigitsUsed
        }

        // ── 式の評価 ───────────────────────────────────────────────
        let exprStr = buildExprString(tokens)

        guard let result = ExprParser.evaluate(exprStr) else {
            return .syntaxError
        }

        // ── 結果判定（浮動小数点の誤差を考慮して1e-9以内を正解とする）──
        return abs(result - 10.0) < 1e-9 ? .correct : .wrongAnswer
    }

    /// トークン配列を評価用の式文字列に変換する。
    /// 表示用の記号（× ÷ −）を計算用記号（* / -）に置き換える。
    private static func buildExprString(_ tokens: [ExprToken]) -> String {
        tokens.map { token -> String in
            switch token.type {
            case .digit(let v, _): return "\(v)"
            case .op(let s):
                switch s {
                case "×": return "*"
                case "÷": return "/"
                case "−": return "-"
                default:  return s
                }
            case .paren(let s): return s
            }
        }.joined()
    }

    /// 入力途中の式を部分評価する。構文が成立していれば現在の値を返し、不完全なら nil を返す。
    /// ExpressionDisplay の「途中計算表示」に使用する（全数字を使い切っていなくてもよい）。
    static func partialEvaluate(tokens: [ExprToken]) -> Double? {
        guard !tokens.isEmpty else { return nil }
        return ExprParser.evaluate(buildExprString(tokens))
    }
}

// MARK: - 式パーサー（再帰下降法）

/// 文字列の四則演算式を評価して Double を返す内部パーサー。
/// ÷0・構文エラーは nil を返す（クラッシュしない）。
///
/// ★ 再帰下降法とは？ ★
///   文法のルールをそのまま関数に落とし込む方式。
///   「掛け算は足し算より先に計算する」という優先順位が
///   parseTerm() → parseExpr() の呼び出し順として自然に表現される。
///
///   文法ルール（BNF記法）:
///     expression := term (('+' | '-') term)*
///     term       := factor (('*' | '/') factor)*
///     factor     := '-' factor | '(' expression ')' | number
private struct ExprParser {

    let tokens: [String]  // tokenize() で分割済みのトークン列
    var pos:    Int = 0   // 現在読んでいる位置（0から始まる）

    // MARK: エントリーポイント

    /// 文字列を受け取り評価結果を返す。
    /// 構文エラーや÷0があれば nil を返す。
    static func evaluate(_ expr: String) -> Double? {
        var parser = ExprParser(tokens: tokenize(expr))
        guard let result = parser.parseExpr() else { return nil }
        // 全トークンを消費できたときだけ有効な式とみなす（余りがあれば構文エラー）
        guard parser.pos == parser.tokens.count else { return nil }
        return result
    }

    // MARK: 字句解析（文字列 → トークン列）

    /// 文字列を数字・記号ごとのトークンに分割する。
    /// 例: "12+3*4" → ["12", "+", "3", "*", "4"]
    private static func tokenize(_ str: String) -> [String] {
        var result: [String] = []
        var i = str.startIndex
        while i < str.endIndex {
            let c = str[i]
            if c.isNumber {
                // 連続する数字を1つのトークンにまとめる（1桁しか出ないが念のため）
                var num = String(c)
                var j   = str.index(after: i)
                while j < str.endIndex, str[j].isNumber {
                    num.append(str[j])
                    j = str.index(after: j)
                }
                result.append(num)
                i = j
            } else {
                result.append(String(c))
                i = str.index(after: i)
            }
        }
        return result
    }

    // MARK: 構文解析（再帰下降）

    // expression := term (('+' | '-') term)*
    // 足し算・引き算を左から順に処理する
    mutating func parseExpr() -> Double? {
        guard var left = parseTerm() else { return nil }
        while pos < tokens.count, tokens[pos] == "+" || tokens[pos] == "-" {
            let op = tokens[pos]; pos += 1
            guard let right = parseTerm() else { return nil }
            left = op == "+" ? left + right : left - right
        }
        return left
    }

    // term := factor (('*' | '/') factor)*
    // 掛け算・割り算を左から順に処理する（足し算より先に評価されるため、こちらが深い）
    mutating func parseTerm() -> Double? {
        guard var left = parseFactor() else { return nil }
        while pos < tokens.count, tokens[pos] == "*" || tokens[pos] == "/" {
            let op = tokens[pos]; pos += 1
            guard let right = parseFactor() else { return nil }
            if op == "/" {
                guard right != 0 else { return nil }  // ÷0 は無効（nilを返す）
                left /= right
            } else {
                left *= right
            }
        }
        return left
    }

    // factor := '-' factor | '(' expression ')' | number
    // 単項マイナス・括弧・数値リテラルを処理する
    mutating func parseFactor() -> Double? {
        guard pos < tokens.count else { return nil }

        // 単項マイナス（例: -5）
        if tokens[pos] == "-" {
            pos += 1
            guard let v = parseFactor() else { return nil }
            return -v
        }

        // 括弧（例: (1+2)）
        if tokens[pos] == "(" {
            pos += 1
            guard let v = parseExpr() else { return nil }
            guard pos < tokens.count, tokens[pos] == ")" else { return nil }
            pos += 1
            return v
        }

        // 数値リテラル（例: 7）
        if let d = Double(tokens[pos]) {
            pos += 1
            return d
        }

        return nil  // 解析できなかった（構文エラー）
    }
}
