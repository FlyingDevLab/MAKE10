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
//   - 式の提出と判定
//   - ヒント表示（全モード共通）：答えをバナー表示、プレイヤーは引き続き回答
//   - 「作れない！」宣言（モードCのみ）
//   - セッション記録（正解数・ヒント使用数など）

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
    case declared  // 「作れない！」宣言後・不正解（モードC：解を表示してから次へ）
}

// MARK: - セッション記録

struct TenPuzzleSessionRecord {
    var mode:       TenPuzzleMode = .modeA
    var correct:    Int           = 0  // 正解数（ヒント使用分を含む）
    var hintUsed:   Int           = 0  // ヒントを見て正解した数
    var impossible: Int           = 0  // 「作れない！」で正解した数（モードCのみ）
    var total:      Int           = TenPuzzleMode.problemsPerSession

    /// ヒントなしで自力で正解した数
    var selfSolved: Int { correct - hintUsed - impossible }
}

// MARK: - ViewModel

@Observable
final class TenPuzzleViewModel {

    private enum C {
        static let correctFeedback: Double = 1.0   // 正解フィードバック表示時間（秒）← 変更可
        static let wrongFeedback:   Double = 0.8   // 不正解フィードバック表示時間（秒）← 変更可
        static let declaredDisplay: Double = 3.5   // 宣言不正解時の解表示時間（秒）← 変更可
    }

    // MARK: ゲームフェーズ・モード

    var phase:        TenPuzzlePhase = .home
    var selectedMode: TenPuzzleMode  = .modeA

    // MARK: 問題管理

    var pool:           [TenPuzzleProblem] = []
    var problemIndex:   Int                = 0
    var currentProblem: TenPuzzleProblem?

    var problemNumber: Int { min(problemIndex + 1, TenPuzzleMode.problemsPerSession) }

    // MARK: 式の状態

    var tokens:       [ExprToken]           = []
    var usedSlots:    Set<Int>              = []
    var problemState: TenPuzzleProblemState = .solving
    var lastJudgment: TenPuzzleJudgment?    = nil
    /// 「作れない！」宣言が不正解だったときに表示する解の文字列
    var shownHint:    String?               = nil

    // MARK: ヒント
    //
    // ★ ヒントの設計方針 ★
    //   ヒントボタンを押すと答えをバナー表示するが、問題は自動で進まない。
    //   プレイヤーは答えを見ながら自分でトークンを組み立てて提出する。
    //   ヒントを見て正解した問題は record.hintUsed にカウントされる。

    /// ヒントボタンを押したかどうか
    var hintShown: Bool = false

    /// ヒントバナーに表示するテキスト。
    /// 解ける問題なら解の例、不可能問題なら「作れません」メッセージ。
    var hintBannerText: String? {
        guard hintShown else { return nil }
        return currentProblem?.example ?? "この問題は10を作れません"
    }

    // MARK: 途中計算

    /// 現在の式の途中計算値。式が評価できれば値を返し、不完全なら nil。
    var liveValue: Double? {
        guard !tokens.isEmpty, problemState == .solving else { return nil }
        return TenPuzzleValidator.partialEvaluate(tokens: tokens)
    }

    // MARK: スコア・記録

    var record = TenPuzzleSessionRecord()

    // MARK: セッション世代番号（asyncAfter の競合防止）
    private var sessionGeneration: Int = 0

    // MARK: - ゲーム開始

    func startSession(mode: TenPuzzleMode) {
        selectedMode      = mode
        pool              = TenPuzzleDatabase.pool(for: mode)
        problemIndex      = 0
        record            = TenPuzzleSessionRecord(mode: mode)
        sessionGeneration += 1
        phase             = .playing
        loadCurrentProblem()
    }

    private func loadCurrentProblem() {
        let n = TenPuzzleMode.problemsPerSession
        guard problemIndex < n && problemIndex < pool.count else {
            withAnimation(.easeInOut(duration: 0.3)) { phase = .result }
            return
        }

        currentProblem = pool[problemIndex]
        tokens         = []
        usedSlots      = []
        problemState   = .solving
        lastJudgment   = nil
        shownHint      = nil
        hintShown      = false  // 毎問リセット
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
        clearExpression()
        SoundManager.shared.playTap()
    }

    private func clearExpression() {
        tokens    = []
        usedSlots = []
    }

    // MARK: - 提出

    func submitExpression() {
        guard problemState == .solving else { return }
        guard let problem = currentProblem else { return }

        let judgment = TenPuzzleValidator.judge(tokens: tokens, digits: problem.digits)
        lastJudgment = judgment
        SoundManager.shared.vibrate()

        if judgment == .correct {
            record.correct += 1
            // ヒントを見て正解した場合は hintUsed にカウント
            if hintShown { record.hintUsed += 1 }
            problemState = .correct
            SoundManager.shared.playCorrect()
            scheduleNextProblem(after: C.correctFeedback)

        } else if judgment == .wrongAnswer {
            problemState = .wrong
            SoundManager.shared.playWrong()
            let gen = sessionGeneration
            DispatchQueue.main.asyncAfter(deadline: .now() + C.wrongFeedback) { [weak self] in
                guard let self, self.sessionGeneration == gen else { return }
                withAnimation { self.problemState = .solving }
                self.clearExpression()
            }

        } else {
            // 構文エラー / 数字不足
            problemState = .wrong
            SoundManager.shared.playWrong()
            let gen = sessionGeneration
            DispatchQueue.main.asyncAfter(deadline: .now() + C.wrongFeedback * 0.7) { [weak self] in
                guard let self, self.sessionGeneration == gen else { return }
                withAnimation { self.problemState = .solving }
                if !self.tokens.isEmpty, !self.tokens.last!.isDigit {
                    self.tokens.removeLast()
                }
            }
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
        SoundManager.shared.playTap()
        // hintUsed のカウントは正解時に行う（押しただけでは増えない）
    }

    // MARK: - 「作れない！」宣言（モードCのみ）

    func declareImpossible() {
        guard selectedMode == .modeC else { return }
        guard problemState == .solving else { return }
        guard let problem = currentProblem else { return }

        SoundManager.shared.vibrate()

        let isActuallyImpossible = (problem.difficulty == .impossible)

        if isActuallyImpossible {
            record.correct    += 1
            record.impossible += 1
            if hintShown { record.hintUsed += 1 }  // ヒントを見てから宣言した場合
            lastJudgment       = .correct
            problemState       = .correct
            SoundManager.shared.playCorrect()
            scheduleNextProblem(after: C.correctFeedback)
        } else {
            // 不正解：実は作れる問題だった → 解を表示してから次へ
            shownHint    = problem.example
            lastJudgment = .wrongAnswer
            problemState = .declared
            SoundManager.shared.playWrong()
            scheduleNextProblem(after: C.declaredDisplay)
        }
    }

    // MARK: - 次の問題へ

    private func scheduleNextProblem(after delay: Double) {
        let gen = sessionGeneration
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self, self.sessionGeneration == gen else { return }
            self.problemIndex += 1
            withAnimation(.easeInOut(duration: 0.3)) {
                self.loadCurrentProblem()
            }
        }
    }

    // MARK: - ホームへ戻る

    func returnToHome() {
        withAnimation(.easeInOut(duration: 0.3)) { phase = .home }
    }

    // MARK: - Suspend / Resume（互換性維持）
    func suspend() {}
    func resume()  {}
}
