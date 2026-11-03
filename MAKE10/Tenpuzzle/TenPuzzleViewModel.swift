//
//  TenPuzzleViewModel.swift
//  FDL-TenBlitz
//
//  Created by 空飛ぶ研究室(FlyingDevLab) on 2026/06/13.
//

// 四則演算テンパズルのゲームロジック全体を制御するViewModel。
//
// ★ このファイルの責務 ★
//   - ゲームフェーズの管理（home → playing → result）
//   - 式トークンの追加・削除・リセット
//     ※ 数字の直後に数字を置けない（12のような結合を防ぐ）
//   - 式の提出と判定（不正解なら同じ問題にもう一度。式は消さない）
//   - ヒント表示（全モード共通）：答えをバナー表示。使うとスコアがそこで止まる
//   - 「作れない！」宣言（チャレンジのみ）：外すとクリアタイムに1分足す
//   - スコア・出題数・クリアタイムの管理と、ベスト記録の保存
//   ルールの考え方は TenPuzzleMode の「出題数とスコアの決まり」を参照。

import SwiftUI
import Combine

// MARK: - ゲームフェーズ

enum TenPuzzlePhase: Equatable {
    case home     // モード選択画面
    case playing  // ゲームプレイ中
    case result   // 結果画面（セッション終了後）
}

// MARK: - 1問ごとの状態

/// .solving のときだけ式の操作ができる。
enum TenPuzzleProblemState: Equatable {
    case solving   // 回答中（式を組み立て中）
    case correct   // 正解フィードバック表示中（次の問題に自動で移行）
    case wrong     // 不正解フィードバック表示中（同じ問題に再挑戦）
}

// MARK: - セッション記録

/// 1回のプレイの結果。結果画面はこれだけを見て描く。
struct TenPuzzleSessionRecord {
    var mode:          TenPuzzleMode = .modeA
    var score:         Int           = 0      // ヒントを使わずに続けて正解した数
    var questionCount: Int           = 0      // 遊んだ問題数
    var hintUsed:      Int           = 0      // ヒントを使った問題の数
    var impossible:    Int           = 0      // 「作れない！」で正解した数（チャレンジのみ）
    var penalty:       TimeInterval  = 0      // 「作れない！」を外して足された秒数
    /// クリアタイム（秒。ペナルティ込み）。満点で終わったときだけ入る。
    var clearTime:     TimeInterval? = nil
    /// 今回でベスト記録（クリアならタイム、そうでなければ連続正解）を更新したか
    var isNewBest:     Bool          = false

    var isCleared: Bool { clearTime != nil }
}

// MARK: - ViewModel

@Observable
final class TenPuzzleViewModel {

    private enum C {
        static let correctFeedback: Double = 1.0   // 正解フィードバック表示時間（秒）← 変更可
        static let wrongFeedback:   Double = 0.8   // 不正解フィードバック表示時間（秒）← 変更可
        static let declaredDisplay: Double = 1.6   // 「作れない！」を外したときのメッセージ表示時間（秒）← 変更可
    }

    // MARK: ゲームフェーズ・モード

    var phase:        TenPuzzlePhase = .home
    var selectedMode: TenPuzzleMode  = .modeA

    // MARK: 問題管理

    private var supplier = TenPuzzleProblemSupplier(mode: .modeA)
    var currentProblem: TenPuzzleProblem?

    /// 何問目か（1始まり。出題した時点で増える）
    private(set) var problemNumber: Int = 0

    /// 進行表示（n / 総数）の分母。「この先いくつ遊べるか」をそのまま出す。
    ///   ノーヒントで続いている … maxQuestions 問目まで遊べる
    ///   ヒントを使った         … minQuestions 問目までは遊べる。それを越えていたら今の問題が最後
    /// 分母を maxQuestions に固定していると、11問目で「11 / 20」と出した直後に
    /// ヒントを使った人がその問題で終わってしまい、打ち切られたように見える。
    var problemTotal: Int {
        streakActive ? TenPuzzleMode.maxQuestions : max(TenPuzzleMode.minQuestions, problemNumber)
    }

    // MARK: 式の状態

    var tokens:       [ExprToken]           = []
    var usedSlots:    Set<Int>              = []
    var problemState: TenPuzzleProblemState = .solving
    var lastJudgment: TenPuzzleJudgment?    = nil

    // MARK: スコア

    /// ヒントを使わずに続けて正解した数
    private(set) var score: Int = 0
    /// まだヒントを使っていないか（false になると加点が止まり、出題も minQuestions 問目で終わる）
    private(set) var streakActive: Bool = true

    // MARK: ヒント
    //
    // ★ ヒントの設計方針 ★
    //   ヒントボタンを押すと答えをバナー表示するが、問題は自動で進まない。
    //   プレイヤーは答えを見ながら自分でトークンを組み立てて提出する。
    //   初めて使ったときにスコアが止まる（その問題も加点されない）。

    /// 今の問題でヒントボタンを押したかどうか
    var hintShown: Bool = false
    /// このヒントでスコアが止まったか（バナーに「スコアは N で止まります」を出す）
    private(set) var hintStoppedScore: Bool = false

    /// ヒントバナーに表示する内容。
    /// 解ける問題なら解の例（式そのものなので翻訳不要）、
    /// 不可能問題なら固定メッセージ（要翻訳）を返す。
    ///
    /// ★ enum で2種類を分けている理由 ★
    ///   解の例（"0+0+1+9" など）は数式そのものであり、どの言語でも
    ///   共通の文字列として表示すればよい（翻訳の必要がない）。
    ///   一方「作れません」は言語ごとの文言が必要になる。
    ///   これを1つの String? に混ぜて持たせると、View 側で
    ///   「翻訳が要る文字列」と「要らない文字列」を区別できず、
    ///   String のまま Text() に渡すしかなくなる（＝翻訳が効かない原因）。
    ///   enum で分けることで、View は迷わず正しい Text() の呼び方を選べる。
    enum HintBannerContent {
        case example(String)           // 解の例（数式）。翻訳不要でそのまま表示。
        case impossibleMessage         // 「この問題は10を作れません」。翻訳が必要。
    }

    var hintBannerContent: HintBannerContent? {
        guard hintShown else { return nil }
        if let example = currentProblem?.example {
            return .example(example)
        }
        return .impossibleMessage
    }

    // MARK: 途中計算

    /// 現在の式の途中計算値。計算できる形でなければ nil。
    /// ÷0 を含むと無限大か NaN になる（View が「0では割れない」と出す）。
    var liveValue: Double? {
        guard !tokens.isEmpty, problemState == .solving else { return nil }
        return TenPuzzleValidator.partialEvaluate(tokens: tokens)
    }

    // MARK: 記録

    var record = TenPuzzleSessionRecord()

    /// 今の問題で「作れない！」を外したか（ペナルティは1問につき1回だけ）
    private var missDeclared = false

    // ★ クリアタイムの計り方 ★
    //   画面には時計を出さないが、裏で経過時間を足していく。
    //   アプリが裏に回っている間は数えない（電話やおやつで中断しても損をしないように）。
    private var elapsedBeforePause: TimeInterval = 0
    private var activeSince:        Date?        = nil

    private var elapsed: TimeInterval {
        elapsedBeforePause + (activeSince.map { Date().timeIntervalSince($0) } ?? 0)
    }

    // MARK: セッション世代番号（asyncAfter の競合防止）
    private var sessionGeneration: Int = 0

    // MARK: - ベスト記録（ホーム・結果画面用）

    /// 連続正解のベスト（未記録は0）
    func bestStreak(for mode: TenPuzzleMode) -> Int {
        ScoreBoard.highScore(for: mode.bestStreakKey)
    }

    /// クリアタイムのベスト（未クリアは nil）
    func bestTime(for mode: TenPuzzleMode) -> TimeInterval? {
        ScoreBoard.bestTime(for: mode.bestTimeKey)
    }

    /// 秒を m:ss の形にする。1/100 秒まで出すと競技的になりすぎるので秒までにしている。
    static func formatTime(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    // MARK: - ゲーム開始

    func startSession(mode: TenPuzzleMode) {
        selectedMode       = mode
        supplier           = TenPuzzleProblemSupplier(mode: mode)
        problemNumber      = 0
        score              = 0
        streakActive       = true
        record             = TenPuzzleSessionRecord(mode: mode)
        elapsedBeforePause = 0
        activeSince        = Date()
        sessionGeneration += 1
        phase              = .playing
        loadNextProblem()
    }

    private func loadNextProblem() {
        guard let problem = supplier.next() else {
            // 問題データが読めなかったとき（通常は起きない）。何も出せないのでホームへ戻す
            phase = .home
            return
        }
        problemNumber   += 1
        currentProblem   = problem
        tokens           = []
        usedSlots        = []
        problemState     = .solving
        lastJudgment     = nil
        hintShown        = false  // 毎問リセット
        hintStoppedScore = false
        missDeclared     = false
    }

    // MARK: - 式の操作

    /// 数字タイル（slot番号）がタップされたとき、式にdigitトークンを追加する。
    ///
    /// ★ 数字の結合を防ぐ guard ★
    ///   直前のトークンが数字のとき、さらに数字を追加すると "12" のように
    ///   2桁の数として評価されてしまう（例: 1と2で12を作る）。
    ///   このガードで「数字の直後には数字を置けない」というルールを強制する。
    func tapDigit(slot: Int) {
        guard problemState == .solving else { return }
        guard let problem = currentProblem else { return }
        guard !usedSlots.contains(slot) else { return }
        // 直前のトークンが数字なら追加不可（数字の結合 = ルール違反）
        guard !(tokens.last?.isDigit == true) else { return }

        tokens.append(ExprToken(type: .digit(value: problem.digits[slot], slot: slot)))
        usedSlots.insert(slot)
        SoundManager.shared.playTap()
    }

    func tapOperator(_ op: String) {
        guard problemState == .solving else { return }
        tokens.append(ExprToken(type: .op(op)))
        SoundManager.shared.playTap()
    }

    func tapParen(_ p: String) {
        guard problemState == .solving else { return }
        tokens.append(ExprToken(type: .paren(p)))
        SoundManager.shared.playTap()
    }

    func deleteLastToken() {
        guard problemState == .solving, !tokens.isEmpty else { return }
        let last = tokens.removeLast()
        if let slot = last.slot { usedSlots.remove(slot) }
        SoundManager.shared.playTap()
    }

    func resetExpression() {
        guard problemState == .solving else { return }
        tokens    = []
        usedSlots = []
        SoundManager.shared.playTap()
    }

    // MARK: - 提出

    func submitExpression() {
        guard problemState == .solving else { return }
        guard let problem = currentProblem else { return }

        let judgment = TenPuzzleValidator.judge(tokens: tokens, digits: problem.digits)
        lastJudgment = judgment
        SoundManager.shared.vibrate()

        if judgment == .correct {
            finishProblem()
        } else {
            // 不正解でも問題は進めない。式も消さないので、少し直してまた出せる
            // （途中の計算結果は式の横にすでに出ている）。
            showWrongFeedback(for: judgment == .wrongAnswer ? C.wrongFeedback : C.wrongFeedback * 0.7)
        }
    }

    // MARK: - ヒント（全モード共通）
    //
    // ヒントボタンを押すと答えをバナー表示する。問題は進まない。
    // プレイヤーは答えを参照しながら自分でトークンを組み立てて提出する。

    func showHint() {
        guard problemState == .solving else { return }
        guard !hintShown else { return }  // 2回押し防止
        hintShown = true
        record.hintUsed += 1
        if streakActive {
            // ここでスコアが止まる。分母（problemTotal）もこの時点で変わる
            streakActive     = false
            hintStoppedScore = true
        }
        SoundManager.shared.playTap()
    }

    // MARK: - 「作れない！」宣言（チャレンジのみ）

    func declareImpossible() {
        guard selectedMode.allowsImpossible else { return }
        guard problemState == .solving else { return }
        guard let problem = currentProblem else { return }

        SoundManager.shared.vibrate()

        if problem.solutionCount == 0 {
            record.impossible += 1
            lastJudgment = .correct
            finishProblem()
        } else {
            // 外れ。問題は進めないしスコアも減らないが、クリアタイムには足す。
            // 同じ問題で何度押しても足すのは1回だけ（誤タップで倍にしないため）。
            let penalized = !missDeclared
            if penalized {
                missDeclared    = true
                record.penalty += TenPuzzleMode.impossibleMissPenalty
            }
            lastJudgment = .actuallySolvable(penalized: penalized)
            showWrongFeedback(for: C.declaredDisplay)
        }
    }

    // MARK: - 正解・不正解の後始末

    private func showWrongFeedback(for delay: Double) {
        problemState = .wrong
        SoundManager.shared.playWrong()
        let gen = sessionGeneration
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self, self.sessionGeneration == gen else { return }
            withAnimation { self.problemState = .solving }
        }
    }

    /// 正解（式か「作れない！」）したときの処理。スコアを数えて、次の問題か結果画面へ進む。
    private func finishProblem() {
        problemState = .correct
        SoundManager.shared.playCorrect()

        // ヒントを一度でも使っていたら加点しない（連続正解はそこで止まっている）
        if streakActive { score += 1 }
        // ヒントを見ずに正解したときだけエネルギーを +1。
        // スコアが止まったあとでも、自分の力で解いた問題は数える。
        if !hintShown { EnergyStore.shared.earn(EnergyRewards.perCorrect) }

        // 満点で終わったときだけタイムを確定させる。正解した瞬間に止めるので、このあとの余韻は記録に入らない。
        // score が maxQuestions に届くのは全問ノーヒント正解のときだけ（不正解では問題が進まない）。
        if score >= TenPuzzleMode.maxQuestions {
            record.clearTime = elapsed + record.penalty
        }

        // 上限に達したか、ヒントを使ったうえで minQuestions 問目まで来たら終わり
        let done = problemNumber >= TenPuzzleMode.maxQuestions
                || (!streakActive && problemNumber >= TenPuzzleMode.minQuestions)

        let gen = sessionGeneration
        DispatchQueue.main.asyncAfter(deadline: .now() + C.correctFeedback) { [weak self] in
            guard let self, self.sessionGeneration == gen else { return }
            withAnimation(.easeInOut(duration: 0.3)) {
                if done {
                    self.finishSession()
                } else {
                    self.loadNextProblem()
                }
            }
        }
    }

    // MARK: - 結果

    private func finishSession() {
        activeSince          = nil
        record.score         = score
        record.questionCount = problemNumber

        // クリアしたらタイム、そうでなければ連続正解の数をベスト記録と比べる。
        // 満点は誰でも同じ点なので、クリアしたモードで追う記録はタイムだけになる。
        if let time = record.clearTime {
            record.isNewBest = ScoreBoard.saveIfFaster(time: time, for: selectedMode.bestTimeKey)
            ScoreBoard.saveIfBetter(score: score, for: selectedMode.bestStreakKey)
        } else {
            record.isNewBest = ScoreBoard.saveIfBetter(score: score, for: selectedMode.bestStreakKey)
        }

        // クリアボーナス = スコア × モードごとの倍率。10問・20問続けて正解したらさらに上乗せする。
        // リザルト画面でまとめて増える演出を見せる
        let bonusRate: Double = {
            switch selectedMode {
            case .modeA: return EnergyRewards.tenPuzzleBonusRateA
            case .modeB: return EnergyRewards.tenPuzzleBonusRateB
            case .modeC: return EnergyRewards.tenPuzzleBonusRateC
            }
        }()
        var bonus = Double(score) * bonusRate
        if score >= TenPuzzleMode.maxQuestions {
            bonus += EnergyRewards.tenPuzzleStreakBonus20
        } else if score >= TenPuzzleMode.minQuestions {
            bonus += EnergyRewards.tenPuzzleStreakBonus10
        }
        EnergyStore.shared.grantClearBonus(bonus)
        GameDailyBonus.shared.claim(.tenPuzzle)   // その日はじめてなら「きょう はじめての ボーナス」（GameDailyBonus.swift を参照）
        phase = .result
    }

    // MARK: - ホームへ戻る

    func returnToHome() {
        activeSince = nil
        sessionGeneration += 1   // 予約済みの「次の問題へ」を捨てる
        withAnimation(.easeInOut(duration: 0.3)) { phase = .home }
    }

    // MARK: - Suspend / Resume
    //
    // アプリが裏に回る・画面を離れるときに suspend、戻ってきたときに resume が呼ばれる。
    // 裏にいた時間をクリアタイムに数えないために使う。

    func suspend() {
        guard let since = activeSince else { return }
        elapsedBeforePause += Date().timeIntervalSince(since)
        activeSince = nil
    }

    func resume() {
        guard phase == .playing, activeSince == nil else { return }
        activeSince = Date()
    }
}
