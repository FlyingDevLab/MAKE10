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
//   TenPuzzleMode       … ゲームモード（modeA / modeB / modeC）と、出題数・スコアの決まり
//   ExprToken           … 式を構成するトークン（数字・演算子・括弧）
//   TenPuzzleJudgment   … 式の判定結果（正解・不正解・構文エラーなど）
//   TenPuzzleDatabase   … JSONから問題を読み込むデータベース（遅延ロード）
//   TenPuzzleProblemSupplier … モードに合った問題を1問ずつ出す
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
/// 出題範囲は難易度コード（easy / normal / hard / impossible）とは別に、
/// 「＋ − だけで作れるか」で分けている（TenPuzzleDatabase.canMakeWithPlusMinus を参照）。
///
/// ★ rawValue（modeA など）を変えない理由 ★
///   ベスト記録のキー（UDKey.tenPuzzleBestStreakA など）がモードと対応しているため。
///   画面に出す名前は title で変えられる。
enum TenPuzzleMode: String, CaseIterable {
    case modeA  // ふつう：＋ − だけで作れる問題（175問）
    case modeB  // むずかしい：10を作れる問題すべて（552問）
    case modeC  // チャレンジ：＋ − では作れない問題（377問）＋ 作れない問題（163問）

    var icon: String {
        switch self {
        case .modeA: return "⭐️"
        case .modeB: return "⭐️⭐️"
        case .modeC: return "⭐️⭐️⭐️"
        }
    }

    /// ★ String ではなく LocalizedStringKey を返す理由 ★
    ///   String型のまま渡すと Xcode のビルド時文字列抽出が効かず、
    ///   Localizable.xcstrings に登録されないため翻訳が引けなくなる
    ///   （日本語環境でしか正しく表示されない不具合の原因になっていた）。
    ///   リテラルを直接返す形にすることで自動抽出の対象になる。
    var title: LocalizedStringKey {
        switch self {
        case .modeA: return "ふつう"
        case .modeB: return "むずかしい"
        case .modeC: return "チャレンジ"
        }
    }

    // ★ "description" は CustomStringConvertible が要求する名前と衝突するため
    //   "subtitle" を使う。衝突するとprint(mode)で予期せぬ挙動が起きる。
    // ★ LocalizedStringKey を返す理由は title と同じ（このファイル冒頭のコメント参照）★
    var subtitle: LocalizedStringKey {
        switch self {
        case .modeA: return "＋と−だけで作れる問題。\nまずはここから。"
        case .modeB: return "どの問題も10を作れる。\n×と÷も使ってみよう。"
        case .modeC: return "＋と−では作れない問題に、作れない問題もまざる。\n見やぶったら「作れない！」。"
        }
    }

    /// 作れない問題がまざるか（「作れない！」ボタンを出すか）
    var allowsImpossible: Bool { self == .modeC }

    /// 連続正解のベストを保存するキー
    var bestStreakKey: String {
        switch self {
        case .modeA: return UDKey.tenPuzzleBestStreakA
        case .modeB: return UDKey.tenPuzzleBestStreakB
        case .modeC: return UDKey.tenPuzzleBestStreakC
        }
    }

    /// クリアタイムのベストを保存するキー
    var bestTimeKey: String {
        switch self {
        case .modeA: return UDKey.tenPuzzleBestTimeA
        case .modeB: return UDKey.tenPuzzleBestTimeB
        case .modeC: return UDKey.tenPuzzleBestTimeC
        }
    }

    var color: Color {
        switch self {
        case .modeA: return .green
        case .modeB: return .orange
        case .modeC: return .red
        }
    }

    // ★ 出題数とスコアの決まり ★
    //   スコアは「ヒントを使わずに続けて正解した数」。ヒントを使った時点で止まり、
    //   以後は正解しても増えない。まちがえた（10にならなかった）だけでは止まらない。
    //   ヒントを使っても minQuestions 問目までは必ず遊べる。
    //   その時点でまだヒントを使っていなければ、maxQuestions 問目まで続く。
    //
    //   上限が無いと、ふつうは「＋側と−側に分けて差が10になる組を探す」コツが
    //   分かればほぼ全問解けてしまい、記録が実力ではなく根気の記録になる。
    //   上限を置くと maxQuestions 点が満点になり、ふつうを取り切ったら
    //   むずかしいへ、という3モードの階段がはじめて機能する。
    //
    // ★ 満点とクリアタイム ★
    //   maxQuestions 問すべてをヒントなしで正解すると「クリア」。
    //   不正解では問題が進まないので、あきらめずに粘れば必ず満点になる。
    //   満点は誰でも同じ点なので、クリアしたときは所要タイムを記録にする。
    //   プレイ中は時間を見せない。画面に時計があると、計測のつもりでも
    //   制限時間と同じ焦りを生むため。
    //   （Web 版 flyingdevlab.com/kids/ten-puzzle/ と同じルール）

    /// ヒントを使っても必ず遊べる問題数
    static let minQuestions: Int = 10   // ← 変更可
    /// ヒントを使わなければ続けられる問題数（＝満点）
    static let maxQuestions: Int = 20   // ← 変更可

    /// 「作れない！」を外したときにクリアタイムへ足す秒数。
    ///
    /// ★ なぜ代償が必要か ★
    ///   外しても問題が進まないので、代償が無いと「まず押して、作れると分かってから解を探す」
    ///   のが最適手になり、チャレンジの山場（解が無いと確信するまで探す判断）が消えてしまう。
    ///   タイムにだけ効かせるので、記録を狙わない子には何も起きない（スコアも減らない）。
    ///   足すのは1問につき1回だけ。ダブルタップや連打で倍にしないため。
    ///   こたえあわせの不正解には代償を付けない。式が10にならないのは作りかけの試行で、
    ///   「作れない！」は結論の宣言だから。
    ///   ※ 秒数を変えたら、メッセージ「この問題は作れるよ（タイム +1分）」と
    ///     ホーム画面のルール説明も直すこと。
    static let impossibleMissPenalty: TimeInterval = 60

    /// チャレンジで10問ごとに混ぜる「作れない問題」の数。
    /// 毎回ちょうど同じ数だと、数えれば最後の数問が読めてしまうので幅を持たせる。
    static let impossiblePer10: ClosedRange<Int> = 2...4
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

/// 式の判定や「作れない！」宣言の結果。
/// Viewはこれをもとにフィードバックの色と文言を切り替える。
enum TenPuzzleJudgment: Equatable {
    case correct              // ✅ 式の値が10になった（または「作れない！」が当たった）
    case wrongAnswer          // ❌ 式は正しいが10にならない（÷0 もここ）
    case notAllDigitsUsed     // ⚠️ 4つの数字を全部使っていない
    case syntaxError          // ⚠️ 式が不完全または構文エラー
    /// ❌ 「作れない！」と宣言したが、実は作れる問題だった。
    /// penalized はこの宣言でクリアタイムに秒数を足したか（1問につき1回目だけ true）。
    case actuallySolvable(penalized: Bool)

    /// フィードバック表示用の色
    var color: Color {
        self == .correct ? DS.gaugeFull : DS.gaugeWarn
    }

    /// フィードバック表示用のメッセージ
    /// ★ LocalizedStringKey を返す理由は TenPuzzleMode.title と同じ ★
    var message: LocalizedStringKey {
        switch self {
        case .correct:          return "正解！"
        case .wrongAnswer:      return "ちがう…"
        case .notAllDigitsUsed: return "4つ全部使おう"
        case .syntaxError:      return "式が不完全だよ"
        // 2回目以降は何も足さないので、秒数も出さない
        case .actuallySolvable(let penalized):
            return penalized ? "この問題は作れるよ（タイム +1分）" : "この問題は作れるよ"
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

    /// 10を作れる問題（552問）
    static var solvablePool:   [TenPuzzleProblem] { all.filter { $0.solutionCount > 0 } }
    /// 10を作れない問題（163問）
    static var impossiblePool: [TenPuzzleProblem] { all.filter { $0.solutionCount == 0 } }

    /// モードの「作れる問題」の出題範囲。
    static func solvablePool(for mode: TenPuzzleMode) -> [TenPuzzleProblem] {
        switch mode {
        case .modeA: return solvablePool.filter {  canMakeWithPlusMinus($0.digits) }  // 175問
        case .modeB: return solvablePool                                               // 552問
        case .modeC: return solvablePool.filter { !canMakeWithPlusMinus($0.digits) }  // 377問
        }
    }

    /// ＋ と − だけで10を作れるか調べる。
    ///
    /// 単項マイナスは使えないので、先頭に来る数字は必ず＋側になる。
    /// 括弧で 9−(3−4) のように書いても 9−3＋4 と同じなので、
    /// 結局「4つの数字を＋側と−側に分けて、差が10になるか」を見ればよい。
    /// ＋側が空（全部マイナス）の分け方は、先頭に置ける数字が無いので除く（mask は 1 から）。
    static func canMakeWithPlusMinus(_ digits: [Int]) -> Bool {
        for mask in 1..<(1 << digits.count) {
            var sum = 0
            for (i, d) in digits.enumerated() {
                sum += (mask & (1 << i)) != 0 ? d : -d
            }
            if sum == 10 { return true }
        }
        return false
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

// MARK: - 出題係

/// モードに合った問題を1問ずつ出す。
///
/// ★ 袋（bag）方式にしている理由 ★
///   毎回ランダムに1問選ぶと、同じ問題が続けて出ることがある。
///   範囲の全問をシャッフルして袋に入れ、1問ずつ引いて、空になったら混ぜ直して補充する。
///   ふつうは175問あるので、1回（最大20問）の中で同じ問題は出ない。
///
/// ★ チャレンジの「作れない問題」の混ぜ方 ★
///   10問を1区切りにして、その中に作れない問題を 2〜4 問ちらばらせる。
///   1問ごとに確率で決めると、0問の回や7問の回が出てしまい、割合が安定しないため。
struct TenPuzzleProblemSupplier {

    private let solvable:   [TenPuzzleProblem]
    private let impossible: [TenPuzzleProblem]
    private var solvableBag:   [TenPuzzleProblem] = []
    private var impossibleBag: [TenPuzzleProblem] = []
    private var schedule:      [Bool]             = []   // true = 作れない問題を出す

    init(mode: TenPuzzleMode) {
        solvable   = TenPuzzleDatabase.solvablePool(for: mode)
        impossible = mode.allowsImpossible ? TenPuzzleDatabase.impossiblePool : []
    }

    /// 次の1問。問題データが読めなかったときだけ nil。
    mutating func next() -> TenPuzzleProblem? {
        guard !impossible.isEmpty else { return Self.draw(&solvableBag, from: solvable) }

        if schedule.isEmpty {
            let count = Int.random(in: TenPuzzleMode.impossiblePer10)
            schedule = (0..<10).map { $0 < count }.shuffled()
        }
        return schedule.removeLast()
            ? Self.draw(&impossibleBag, from: impossible)
            : Self.draw(&solvableBag,   from: solvable)
    }

    private static func draw(_ bag: inout [TenPuzzleProblem], from pool: [TenPuzzleProblem]) -> TenPuzzleProblem? {
        if bag.isEmpty { bag = pool.shuffled() }
        return bag.popLast()
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
        // ÷0 の結果（無限大・NaN）は 10 との差が 1e-9 未満にならないので、ここで不正解になる
        return abs(result - 10.0) < 1e-9 ? .correct : .wrongAnswer
    }

    /// トークン配列を評価用の式文字列に変換する。
    /// 表示用の記号（× ÷ −）を計算用記号（* / -）に置き換える。
    private static func buildExprString(_ tokens: [ExprToken]) -> String {
        evalSymbols(tokens).joined()
    }

    /// トークン配列を、計算用の記号1つずつの配列にする。
    private static func evalSymbols(_ tokens: [ExprToken]) -> [String] {
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
        }
    }

    /// 組み立て途中の式を、いま計算できるところまで計算する。
    /// ExpressionDisplay の「途中計算表示」に使用する（全数字を使い切っていなくてもよい）。
    ///
    /// 入力の途中では「3 + 4 ×」や「(3 + 4」のように式が閉じていない。
    /// 末尾の記号と開き括弧はまだ書きかけなので外し、閉じていない括弧は
    /// 補って計算する。たとえば「(3 + 4 ×」は「(3 + 4)」として 7 を返す。
    /// 補っても式にならない形は nil。÷0 を含むと無限大か NaN を返す（呼び出し側で isFinite を見る）。
    static func partialEvaluate(tokens: [ExprToken]) -> Double? {
        var symbols = evalSymbols(tokens)
        while let last = symbols.last, ["+", "-", "*", "/", "("].contains(last) { symbols.removeLast() }
        guard !symbols.isEmpty else { return nil }

        var open = 0
        for s in symbols {
            if s == "(" { open += 1 }
            if s == ")" { open -= 1 }
            if open < 0 { return nil }   // 閉じ括弧が多すぎる
        }
        symbols += Array(repeating: ")", count: open)

        return ExprParser.evaluate(symbols.joined())
    }

    /// 計算結果を表示用の文字列にする。割り切れないときは分数で出す。
    ///
    /// 0.333 と出すより 1/3 の方が、こどもにも次の一手が考えやすい。
    /// 1桁の数字4つと四則演算で作れる分母は 9×9×9 = 729 までなので、
    /// 1000 までの分母を試せば必ず見つかる。
    static func formatValue(_ value: Double) -> String {
        let sign = value < 0 ? "−" : ""   // 表示に合わせて U+2212 を使う
        let absValue = abs(value)
        for den in 1...1000 {
            let num = (absValue * Double(den)).rounded()
            if abs(absValue * Double(den) - num) < 1e-9 {
                return sign + (den == 1 ? "\(Int(num))" : "\(Int(num))/\(den)")
            }
        }
        return sign + String(format: "%.3f", absValue)   // ここには来ない想定の保険
    }
}

// MARK: - 式パーサー（再帰下降法）

/// 文字列の四則演算式を評価して Double を返す内部パーサー。
/// 構文エラーは nil を返す（クラッシュしない）。
/// ÷0 は構文としては正しいので nil にせず、無限大（0÷0 は NaN）をそのまま返す。
/// 「式が不完全」ではなく「10にならない」「0では割れない」と伝えるため。
///
/// ★ 再帰下降法とは？ ★
///   文法のルールをそのまま関数に落とし込む方式。
///   「掛け算は足し算より先に計算する」という優先順位が
///   parseTerm() → parseExpr() の呼び出し順として自然に表現される。
///
///   文法ルール（BNF記法）:
///     expression := term (('+' | '-') term)*
///     term       := factor (('*' | '/') factor)*
///     factor     := '(' expression ')' | number
///
/// ★ 単項マイナス（-3 のような書き方）には対応していません ★
///   4つの数字と二項演算だけで10を作るゲームなので要らないうえ、
///   使えると「＋ − だけで作れる問題」（ふつう）の分け方が成り立たなくなるため。
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
            // ÷0 は無限大（0÷0 は NaN）になる。10 にはならないので不正解として流れる
            left = op == "/" ? left / right : left * right
        }
        return left
    }

    // factor := '(' expression ')' | number
    // 括弧・数値リテラルを処理する
    mutating func parseFactor() -> Double? {
        guard pos < tokens.count else { return nil }

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
