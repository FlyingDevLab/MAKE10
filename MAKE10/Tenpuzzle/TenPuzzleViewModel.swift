//
//  TenPuzzleViewModel.swift
//  FDL-TenBlitz
//
//  Created by 空飛ぶ研究室(FlyingDevLab) on 2026/06/13.
//

// 四則演算テンパズルのゲームロジック全体を制御するViewModel。
// TenPuzzleView（ルートView）がこのViewModelを @State で1つ持ち、
// フェーズ（.home / .playing / .result）に応じて子Viewを切り替える。
//
// ★ このファイルの責務 ★
//   - ゲームフェーズの管理（home → playing → result）
//   - 式トークンの追加・削除・リセット
//   - 式の提出と判定
//   - ヒント表示・スキップ（モードB）
//   - 「作れない！」宣言（モードC）
//   - タイマー管理（モードCのみ）
//   - セッション記録（正解数・ヒント使用数など）

import SwiftUI
import Combine

// MARK: - ゲームフェーズ

/// TenPuzzleView が参照し、フェーズに応じて表示する画面を切り替える。
enum TenPuzzlePhase: Equatable {
    case home     // モード選択画面
    case playing  // ゲームプレイ中
    case result   // 結果画面（セッション終了後）
}

// MARK: - 1問ごとの状態

/// 問題を解いている最中の細かい状態。
/// .solving のときだけ式の操作ができる。
enum TenPuzzleProblemState: Equatable {
    case solving   // 回答中（式を組み立て中）
    case correct   // 正解フィードバック表示中（次の問題に自動で移行）
    case wrong     // 不正解フィードバック表示中（同じ問題に再挑戦）
    case hinted    // ヒント表示中（モードB：次の問題に自動で移行）
    case declared  // 「作れない！」宣言後・不正解（モードC：ヒントを表示）
}

// MARK: - セッション記録

/// 1セッション（10問）の結果をまとめる構造体。
/// 結果画面（TenPuzzleResultView）に渡して表示する。
struct TenPuzzleSessionRecord {
    var mode:       TenPuzzleMode = .modeA
    var correct:    Int           = 0  // 正解数（ヒント使用分・宣言正解分を含む）
    var hintUsed:   Int           = 0  // ヒントを使って正解した数（モードBのみ）
    var skipped:    Int           = 0  // スキップした数（モードBのみ）
    var impossible: Int           = 0  // 「作れない！」で正解した数（モードCのみ）
    var total:      Int           = TenPuzzleMode.problemsPerSession  // 全問題数

    /// ヒントなしで自力で正解した数
    var selfSolved: Int { correct - hintUsed - impossible }
}

// MARK: - ViewModel

@Observable
final class TenPuzzleViewModel {

    // MARK: 定数
    //
    // ★ private enum C にまとめる理由 ★
    //   マジックナンバーをなくし、値の意味を名前で伝えるため。
    //   GameViewModelと同じ設計方針。

    private enum C {
        static let correctFeedback: Double = 1.0   // 正解フィードバック表示時間（秒）← 変更可
        static let wrongFeedback:   Double = 0.8   // 不正解フィードバック表示時間（秒）← 変更可
        static let hintDisplay:     Double = 3.5   // ヒント表示時間（秒）← 変更可
        static let timerInterval:   Double = 0.01  // タイマーの更新間隔（秒）
    }

    // MARK: ゲームフェーズ・モード

    var phase:        TenPuzzlePhase = .home
    var selectedMode: TenPuzzleMode  = .modeA

    // MARK: 問題管理

    /// 今セッションの問題プール（シャッフル済み）
    var pool:           [TenPuzzleProblem] = []
    /// 現在何問目か（0-based）
    var problemIndex:   Int                = 0
    /// 現在の問題
    var currentProblem: TenPuzzleProblem?

    /// UI表示用の問題番号（1-based）
    var problemNumber: Int { min(problemIndex + 1, TenPuzzleMode.problemsPerSession) }

    // MARK: 式の状態

    /// ユーザーが組み立て中の式トークン列
    var tokens:       [ExprToken]           = []
    /// 使用済みの数字スロット（0〜3）
    var usedSlots:    Set<Int>              = []
    /// 現在の1問ごとの状態
    var problemState: TenPuzzleProblemState = .solving
    /// 直前の判定結果（フィードバック表示に使う）
    var lastJudgment: TenPuzzleJudgment?    = nil
    /// 表示中のヒント文字列（モードB・C）
    var shownHint:    String?               = nil

    // MARK: スコア・記録

    var record = TenPuzzleSessionRecord()

    // MARK: タイマー（モードCのみ）

    /// 残り時間（秒）。モードA・Bは参照しない
    var timeRemaining: Double = 45.0

    /// タイマーの基準時刻（残り時間 = timerSeconds - (now - baseDate)）
    private var timerBaseDate:    Date           = .now
    private var timerCancellable: AnyCancellable?

    // MARK: セッション世代番号
    //
    // ★ 世代番号パターン（GameViewModelのconfettiGenerationと同じ）★
    //   returnToHome() → 新セッション開始 の間に、
    //   旧セッションの asyncAfter クロージャが遅れて発火することがある。
    //   世代番号で「このクロージャは今のセッションのものか？」を確認し、
    //   古い世代のクロージャは何もせず終了させる。

    private var sessionGeneration: Int = 0

    // MARK: - ゲーム開始

    /// モードを選択してセッションを開始する。
    /// pool をシャッフルし、problemIndex をリセットして最初の問題をロードする。
    func startSession(mode: TenPuzzleMode) {
        selectedMode      = mode
        pool              = TenPuzzleDatabase.pool(for: mode)
        problemIndex      = 0
        record            = TenPuzzleSessionRecord(mode: mode)
        sessionGeneration += 1   // 旧セッションの asyncAfter を無効化する
        phase             = .playing
        loadCurrentProblem()
    }

    /// 現在インデックスの問題を読み込んで初期状態にする。
    /// 問題数を超えたらセッション終了（結果画面へ）。
    private func loadCurrentProblem() {
        let n = TenPuzzleMode.problemsPerSession
        guard problemIndex < n && problemIndex < pool.count else {
            // 全問終了 → 結果画面へ
            withAnimation(.easeInOut(duration: 0.3)) { phase = .result }
            return
        }

        currentProblem = pool[problemIndex]
        tokens         = []
        usedSlots      = []
        problemState   = .solving
        lastJudgment   = nil
        shownHint      = nil

        // モードCのみタイマーを起動する
        if let seconds = selectedMode.timerSeconds {
            startTimer(seconds: seconds)
        }
    }

    // MARK: - 式の操作

    /// 数字タイル（slot番号）がタップされたとき、式にdigitトークンを追加する。
    /// すでに使用済みのスロットは無視する（同じ数字を2回使えない）。
    func tapDigit(slot: Int) {
        guard problemState == .solving else { return }
        guard let problem = currentProblem else { return }
        guard !usedSlots.contains(slot) else { return }

        tokens.append(ExprToken(type: .digit(value: problem.digits[slot], slot: slot)))
        usedSlots.insert(slot)
        SoundManager.shared.playTap()
    }

    /// 演算子ボタン（+、−、×、÷）がタップされたとき
    func tapOperator(_ op: String) {
        guard problemState == .solving else { return }
        tokens.append(ExprToken(type: .op(op)))
        SoundManager.shared.playTap()
    }

    /// 括弧ボタン（(、)）がタップされたとき
    func tapParen(_ p: String) {
        guard problemState == .solving else { return }
        tokens.append(ExprToken(type: .paren(p)))
        SoundManager.shared.playTap()
    }

    /// 最後のトークンを1つ削除する（⌫ボタン）
    func deleteLastToken() {
        guard problemState == .solving, !tokens.isEmpty else { return }
        let last = tokens.removeLast()
        // digitトークンを削除したときは、そのslotを使用済みセットからも取り除く
        if let slot = last.slot { usedSlots.remove(slot) }
        SoundManager.shared.playTap()
    }

    /// 式を全クリアする（リセットボタン）。ユーザー操作用：効果音あり。
    func resetExpression() {
        guard problemState == .solving else { return }
        clearExpression()
        SoundManager.shared.playTap()
    }

    /// 式を音なしでクリアする。不正解後の自動リセットなど内部処理用。
    ///
    /// ★ resetExpression() と分ける理由 ★
    ///   asyncAfter で自動リセットするときに効果音を鳴らすと、
    ///   「不正解音の0.8秒後にタップ音が鳴る」という不自然なUXになる。
    ///   ユーザー操作（リセットボタン）と内部処理を明示的に分離することで防ぐ。
    private func clearExpression() {
        tokens    = []
        usedSlots = []
    }

    // MARK: - 提出（= 10？ ボタン）

    /// ユーザーが「こたえる」をタップしたとき呼ばれる。
    /// 式を評価し、結果に応じてフィードバックを表示する。
    func submitExpression() {
        guard problemState == .solving else { return }
        guard let problem = currentProblem else { return }

        let judgment = TenPuzzleValidator.judge(tokens: tokens, digits: problem.digits)
        lastJudgment = judgment
        SoundManager.shared.vibrate()

        if judgment == .correct {
            // ── 正解 ──────────────────────────────────────────────────
            record.correct += 1
            problemState    = .correct
            SoundManager.shared.playCorrect()
            stopTimer()
            scheduleNextProblem(after: C.correctFeedback)

        } else if judgment == .wrongAnswer {
            // ── 答えが違う：フィードバック後に同じ問題を再挑戦 ─────────
            // （式をリセットして再度考えてもらう。問題番号は変わらない）
            problemState = .wrong
            SoundManager.shared.playWrong()
            let gen = sessionGeneration  // クロージャ実行時に世代を検証するため保持
            DispatchQueue.main.asyncAfter(deadline: .now() + C.wrongFeedback) { [weak self] in
                guard let self, self.sessionGeneration == gen else { return }
                withAnimation { self.problemState = .solving }
                self.clearExpression()  // 音なしリセット（効果音の二重再生を防ぐ）
            }

        } else {
            // ── 構文エラー / 数字不足：フィードバックだけ表示して続行 ──
            // （式は消さず、プレイヤーが自分で修正できるようにする）
            problemState = .wrong
            SoundManager.shared.playWrong()
            let gen = sessionGeneration
            DispatchQueue.main.asyncAfter(deadline: .now() + C.wrongFeedback * 0.7) { [weak self] in
                guard let self, self.sessionGeneration == gen else { return }
                withAnimation { self.problemState = .solving }
                // 末尾の不完全なトークン（演算子・括弧）だけ削除して修正しやすくする
                if !self.tokens.isEmpty, !self.tokens.last!.isDigit {
                    self.tokens.removeLast()
                }
            }
        }
    }

    // MARK: - ヒント（モードBのみ）

    /// ヒントボタンをタップしたとき、解の例を表示して正解扱いにする。
    /// ヒント使用は record.hintUsed にカウントされる。
    func useHint() {
        guard selectedMode == .modeB else { return }
        guard problemState == .solving else { return }
        guard let ex = currentProblem?.example else { return }

        shownHint       = ex
        problemState    = .hinted
        record.correct  += 1
        record.hintUsed += 1
        SoundManager.shared.playTap()
        scheduleNextProblem(after: C.hintDisplay)
    }

    // MARK: - スキップ（モードBのみ）

    /// スキップボタンをタップしたとき、次の問題に移る（スコアは増えない）。
    func skipProblem() {
        guard selectedMode == .modeB else { return }
        guard problemState == .solving else { return }
        record.skipped += 1
        scheduleNextProblem(after: 0)
    }

    // MARK: - 「作れない！」宣言（モードCのみ）

    /// プレイヤーが「この問題は10を作れない」と宣言する。
    /// 実際に不可能問題なら正解、作れる問題なら不正解（解を表示）。
    func declareImpossible() {
        guard selectedMode == .modeC else { return }
        guard problemState == .solving else { return }
        guard let problem = currentProblem else { return }

        stopTimer()
        SoundManager.shared.vibrate()

        let isActuallyImpossible = (problem.difficulty == .impossible)

        if isActuallyImpossible {
            // 正解：本当に作れない問題だった
            record.correct    += 1
            record.impossible += 1
            lastJudgment       = .correct
            problemState       = .correct
            SoundManager.shared.playCorrect()
            scheduleNextProblem(after: C.correctFeedback)
        } else {
            // 不正解：実は作れる問題だった → 解を見せる
            shownHint    = problem.example
            lastJudgment = .wrongAnswer
            problemState = .declared
            SoundManager.shared.playWrong()
            scheduleNextProblem(after: C.hintDisplay)
        }
    }

    // MARK: - 次の問題へ

    /// 指定秒後に problemIndex を進めて次の問題をロードする。
    /// 世代番号を検証し、旧セッションのクロージャは無視する。
    private func scheduleNextProblem(after delay: Double) {
        let gen = sessionGeneration  // 現在の世代番号を捕捉する
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self, self.sessionGeneration == gen else { return }  // 旧世代は無視
            self.problemIndex += 1
            withAnimation(.easeInOut(duration: 0.3)) {
                self.loadCurrentProblem()
            }
        }
    }

    // MARK: - タイマー（モードCのみ）

    /// タイマーを開始する。残り時間 seconds 秒からカウントダウンする。
    private func startTimer(seconds: Double) {
        stopTimer()
        timeRemaining = seconds
        // 「(timerSeconds - seconds) 秒前にスタートした」という基準時刻を設定する。
        // → elapsed = now - baseDate = timerSeconds - seconds
        // → timeRemaining = timerSeconds - elapsed = seconds ← 残り時間が正しく復元される
        let timerSeconds = selectedMode.timerSeconds ?? seconds
        timerBaseDate = Date.now.addingTimeInterval(-(timerSeconds - seconds))

        timerCancellable = Timer.publish(every: C.timerInterval, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self, self.problemState == .solving else { return }
                let elapsed        = Date.now.timeIntervalSince(self.timerBaseDate)
                let totalSeconds   = self.selectedMode.timerSeconds ?? 0
                self.timeRemaining = max(0, totalSeconds - elapsed)
                if self.timeRemaining <= 0 { self.handleTimeUp() }
            }
    }

    private func stopTimer() {
        timerCancellable?.cancel()
        timerCancellable = nil
    }

    /// 時間切れ処理：不正解として次の問題へ
    private func handleTimeUp() {
        stopTimer()
        lastJudgment = .wrongAnswer
        problemState = .wrong
        SoundManager.shared.playWrong()
        scheduleNextProblem(after: C.wrongFeedback)
    }

    // MARK: - ホームへ戻る

    func returnToHome() {
        stopTimer()
        withAnimation(.easeInOut(duration: 0.3)) { phase = .home }
    }

    // MARK: - Suspend / Resume（設定パネル・バックグラウンド対応）

    /// 設定パネルが開いたとき・アプリがバックグラウンドに入ったときにタイマーを止める
    func suspend() { stopTimer() }

    /// 設定パネルが閉じたとき・フォアグラウンドに戻ったときにタイマーを再開する
    func resume() {
        // モードC かつ 回答中 かつ プレイ画面のときだけ再開する
        guard selectedMode == .modeC,
              problemState == .solving,
              phase == .playing else { return }
        // 残り時間を引き継いでタイマーを再開する
        startTimer(seconds: timeRemaining)
    }
}
