//
//  JankenViewModel.swift
//  FDL-TenBlitz
//
//  Created by 空飛ぶ研究室(FlyingDevLab) on 2026/06/03.
//

// 指令じゃんけんのゲームロジック・状態管理・タイマーを担うViewModel。
// 難易度に応じた指示列を生成し、タップ判定・ペナルティ・フェーズ切替・シール報酬を一括管理する。
//
// ★ 調整ポイント（C enum） ★
//   penaltySec    … ミス時に加算するペナルティ秒数
//   flashDuration … 正解/不正解フラッシュの表示時間
//   phaseDuration … フェーズ切替テロップの表示時間（挑戦モードのみ）
//   timerInterval … 経過時間タイマーの更新間隔

import SwiftUI

// MARK: - Top-level Enums

/// ゲームの難易度。出題内容・手数・シール倍率を決定する。
enum JankenDifficulty {
    case easy       // かんたん：10回勝て
    case hard       // むずかしい：10回負けろ
    case challenge  // 挑戦：勝て×10→負けろ×10→交互×10

    var totalRounds: Int {
        switch self {
        case .easy, .hard: return 10
        case .challenge:   return 30
        }
    }

    var stickerMultiplier: Int {
        switch self {
        case .easy:      return 1  // ← 変更可
        case .hard:      return 2  // ← 変更可
        case .challenge: return 3  // ← 変更可
        }
    }

    var bestTimeKey: String {
        switch self {
        case .easy:      return UDKey.jankenBestTimeEasy
        case .hard:      return UDKey.jankenBestTimeHard
        case .challenge: return UDKey.jankenBestTimeChallenge
        }
    }

    var labelKey: LocalizedStringKey {
        switch self {
        case .easy:      return "janken_difficulty_easy"
        case .hard:      return "janken_difficulty_hard"
        case .challenge: return "janken_difficulty_challenge"
        }
    }
}

/// じゃんけんの手。emoji・勝敗判定を持つ。
enum JankenHand: CaseIterable {
    case rock, scissors, paper

    var emoji: String {
        switch self {
        case .rock:     return "✊"
        case .scissors: return "✌️"
        case .paper:    return "🖐️"
        }
    }

    /// selfがotherに勝つか（あいこはfalse）
    func beats(_ other: JankenHand) -> Bool {
        switch (self, other) {
        case (.rock, .scissors), (.scissors, .paper), (.paper, .rock): return true
        default: return false
        }
    }
}

/// 現在の指示。勝て／負けろを表す。
enum JankenInstruction {
    case win   // 勝て
    case lose  // 負けろ
}

// MARK: - JankenViewModel

@Observable
final class JankenViewModel {

    // MARK: - Tunable Parameters

    private enum C {
        static let penaltySec:     Double = 5.0   // ← 変更可：ミス時のペナルティ秒数
        static let flashDuration:  Double = 0.25  // ← 変更可：フラッシュ表示時間（秒）
        static let phaseDuration:  Double = 2.0   // ← 変更可：フェーズ切替テロップ表示時間（秒）
        static let timerInterval:  Double = 0.05  // ← 変更可：経過時間タイマーの更新間隔（秒）
        static let countdownTotal: Int    = 5     // ← 変更可：カウントダウン総秒数
    }

    // MARK: - Nested Types

    /// ゲームの状態。Viewの表示切り替えに使う。
    enum Phase: Equatable {
        case idle                       // 難易度選択前
        case countdown(Int)             // カウントダウン中（0=空白, 1, 2, 3）
        case phaseTransition(String)    // フェーズ切替テロップ（ローカライズキー）
        case playing                    // プレイ中
        case finished                   // 終了
    }

    /// 正解/不正解フラッシュの種別。
    enum Flash: Equatable {
        case correct  // 正解：緑
        case wrong    // 不正解：赤
    }

    // MARK: - Published State

    var phase:              Phase             = .idle
    var difficulty:         JankenDifficulty  = .easy
    var cpuHand:            JankenHand        = .rock
    var currentInstruction: JankenInstruction = .win
    var currentRound:       Int              = 0      // 完了済み手数（次の手のindexを兼ねる）
    var missCount:          Int              = 0
    var elapsed:            TimeInterval     = 0.0
    var flash:              Flash?           = nil
    /// タップされた手。ボタンの色変化トリガーとして使う。flashと同じタイミングでクリアされる。
    var tappedHand:         JankenHand?      = nil
    var isNewBest:          Bool             = false

    // MARK: - Derived

    var totalRounds: Int { difficulty.totalRounds }

    /// プログレスバー用（0.0〜1.0）
    var progress: Double {
        totalRounds > 0 ? Double(currentRound) / Double(totalRounds) : 0
    }

    /// 最終正解率（0.0〜1.0）。終了後に参照する。
    var finalAccuracy: Double {
        totalRounds > 0 ? Double(totalRounds - missCount) / Double(totalRounds) : 0
    }

    /// 経過時間の表示文字列（mm:ss.cc 形式）
    var elapsedFormatted: String {
        formatTime(elapsed)
    }

    /// 難易度ごとのベストタイム（記録なしはnil）
    var bestTime: TimeInterval? {
        let v = UserDefaults.standard.double(forKey: difficulty.bestTimeKey)
        return v > 0 ? v : nil
    }

    /// ベストタイムの表示文字列
    var bestTimeFormatted: String? {
        bestTime.map { formatTime($0) }
    }

    /// 挑戦モードの現在フェーズ表示キー（タイトル・ゲーム画面に常時表示）
    var challengePhaseKey: LocalizedStringKey? {
        guard difficulty == .challenge else { return nil }
        switch currentRound {
        case 0..<10:  return "janken_instruction_win"
        case 10..<20: return "janken_instruction_lose"
        default:      return "janken_phase_alternate_short"
        }
    }

    /// フラッシュの色（Viewのオーバーレイで使用）
    var flashColor: Color? {
        switch flash {
        case .correct: return DS.gaugeFull
        case .wrong:   return DS.blitzColor
        case nil:      return nil
        }
    }

    // MARK: - Private State

    private var instructions:   [JankenInstruction] = []
    private var gameTimer:      Timer?               = nil
    private var countdownTimer: Timer?               = nil
    private var isTimerRunning: Bool                 = false
    private var isTapLocked:    Bool                 = false

    // MARK: - Public API

    /// 難易度を指定してゲームを開始する
    func start(difficulty: JankenDifficulty) {
        self.difficulty = difficulty
        instructions    = Self.buildInstructions(for: difficulty)
        currentRound    = 0
        missCount       = 0
        elapsed         = 0.0
        flash           = nil
        tappedHand      = nil  // ボタンフィードバック状態をリセット
        isNewBest       = false
        isTapLocked     = false
        phase           = .countdown(0)
        beginCountdown()
    }

    /// 同じ難易度でリスタート
    func restart() {
        start(difficulty: difficulty)
    }

    /// 難易度選択画面に戻る
    func goToIdle() {
        stopGame()
    }

    /// バックボタン・onDisappearから呼ぶ強制停止
    func stopGame() {
        gameTimer?.invalidate()
        countdownTimer?.invalidate()
        gameTimer      = nil
        countdownTimer = nil
        isTimerRunning = false
        tappedHand     = nil  // ボタンフィードバック状態をリセット
        phase          = .idle
    }

    /// プレイヤーの手をタップ。.playing状態かつロックなしのときのみ有効。
    func tap(_ playerHand: JankenHand) {
        guard case .playing = phase, !isTapLocked else { return }
        isTapLocked = true
        tappedHand  = playerHand  // タップした手を記録（ボタン色変化のトリガー）

        // 勝敗判定（あいこ=不正解）
        let isCorrect: Bool = {
            switch currentInstruction {
            case .win:  return playerHand.beats(cpuHand)
            case .lose: return cpuHand.beats(playerHand)
            }
        }()

        if isCorrect {
            flash = .correct
            SoundManager.shared.playCorrect()
            SoundManager.shared.vibrate()
        } else {
            flash     = .wrong
            elapsed  += C.penaltySec
            missCount += 1
            SoundManager.shared.playWrong()
        }

        currentRound += 1

        let isDone       = currentRound >= totalRounds
        let isTransition = difficulty == .challenge
                           && (currentRound == 10 || currentRound == 20)

        // 通常ケース：次の問題を即座にセット（フラッシュと同時に表示）
        if !isDone && !isTransition {
            nextRound()
        }

        // フラッシュ終了後の後処理
        DispatchQueue.main.asyncAfter(deadline: .now() + C.flashDuration) { [weak self] in
            guard let self else { return }
            self.flash       = nil
            self.tappedHand  = nil  // ボタンフィードバックをクリア
            self.isTapLocked = false

            if isDone {
                self.endGame()
            } else if isTransition {
                let key = self.currentRound == 10
                    ? "janken_telop_lose"
                    : "janken_telop_alternate"
                self.showPhaseTransition(key)
            }
        }
    }

    // MARK: - Private: Countdown

    /// 5秒カウントダウン。5・4は表示せず、3→2→1のみ表示する。
    private func beginCountdown() {
        var tick = 0
        countdownTimer?.invalidate()
        countdownTimer = Timer.scheduledTimer(
            withTimeInterval: 1.0,
            repeats: true
        ) { [weak self] t in
            guard let self else { t.invalidate(); return }
            tick += 1
            // tick=2→"3", tick=3→"2", tick=4→"1", tick=5→開始
            let display = C.countdownTotal - tick
            if display >= 1 && display <= 3 {
                self.phase = .countdown(display)
                SoundManager.shared.playTap()
            }
            if tick >= C.countdownTotal {
                t.invalidate()
                self.countdownTimer = nil
                self.beginPlaying()
            }
        }
    }

    // MARK: - Private: Play

    private func beginPlaying() {
        nextRound()  // 最初の問題をセット
        phase = .playing
        startElapsedTimer()
    }

    private func startElapsedTimer() {
        isTimerRunning = true
        gameTimer?.invalidate()
        gameTimer = Timer.scheduledTimer(
            withTimeInterval: C.timerInterval,
            repeats: true
        ) { [weak self] _ in
            guard let self, self.isTimerRunning else { return }
            self.elapsed += C.timerInterval
        }
    }

    /// 次のラウンドのCPUの手と指示をセット（タップ時にランダム生成）
    /// 前回と同じ手が連続しないよう除外してからランダム選択する
    private func nextRound() {
        let candidates     = JankenHand.allCases.filter { $0 != cpuHand }
        cpuHand            = candidates.randomElement()!
        currentInstruction = instructions[currentRound]
    }

    // MARK: - Private: Phase Transition（挑戦モードのみ）

    /// タイマーを止めてテロップを表示し、終了後にゲームを再開する
    private func showPhaseTransition(_ telopKey: String) {
        isTimerRunning = false
        phase          = .phaseTransition(telopKey)
        DispatchQueue.main.asyncAfter(deadline: .now() + C.phaseDuration) { [weak self] in
            guard let self else { return }
            self.nextRound()
            self.phase          = .playing
            self.isTimerRunning = true
        }
    }

    // MARK: - Private: End Game

    private func endGame() {
        gameTimer?.invalidate()
        gameTimer      = nil
        isTimerRunning = false
        isNewBest      = checkAndSaveBestTime()
        awardStickers()
        SoundManager.shared.playTenClear()
        withAnimation(.easeInOut(duration: 0.3)) {
            phase = .finished
        }
    }

    // MARK: - Private: Sticker Award

    /// クリア枚数×難易度倍率を計算してStickerStoreに追加
    private func awardStickers() {
        var base = 1                     // クリアボーナス
        if finalAccuracy >= 0.5 { base += 1 }  // 50%以上ボーナス
        if finalAccuracy >= 1.0 { base += 1 }  // ノーミスボーナス
        let total = base * difficulty.stickerMultiplier
        for _ in 0..<total {
            StickerStore.shared.addBonusSticker()
        }
    }

    // MARK: - Private: Best Time

    /// 現在タイムが過去最速なら保存してtrueを返す
    private func checkAndSaveBestTime() -> Bool {
        let key  = difficulty.bestTimeKey
        let prev = UserDefaults.standard.double(forKey: key)
        guard elapsed < prev || prev == 0 else { return false }
        UserDefaults.standard.set(elapsed, forKey: key)
        return true
    }

    // MARK: - Private: Instructions Builder

    /// 難易度に応じた指示列を生成する
    private static func buildInstructions(
        for difficulty: JankenDifficulty
    ) -> [JankenInstruction] {
        switch difficulty {
        case .easy:
            return Array(repeating: .win,  count: 10)
        case .hard:
            return Array(repeating: .lose, count: 10)
        case .challenge:
            let wins  = Array(repeating: JankenInstruction.win,  count: 10)
            let loses = Array(repeating: JankenInstruction.lose, count: 10)
            let alt   = (0..<10).map { i in
                i % 2 == 0 ? JankenInstruction.win : JankenInstruction.lose
            }
            return wins + loses + alt
        }
    }

    // MARK: - Private: Formatter

    private func formatTime(_ t: TimeInterval) -> String {
        let m  = Int(t) / 60
        let s  = Int(t) % 60
        let cs = Int((t - Double(Int(t))) * 100)
        return String(format: "%02d:%02d.%02d", m, s, cs)
    }
}
