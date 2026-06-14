//
//  JankenViewModel.swift
//  FDL-TenBlitz
//
//  Created by 空飛ぶ研究室(FlyingDevLab) on 2026/06/03.
//
//  ① 一言サマリ
//  指令じゃんけん（Command Janken）のゲームロジック・状態・タイマー担当ViewModel。
//  「勝て／負けろ」という指示に対し、正しい手をタップして10手（挑戦モードは30手）を
//  最速で答えるゲーム。難易度ごとの指示列生成・勝敗判定・ミスペナルティ・
//  フェーズ切替・シール報酬まで、ロジックをすべてここに集約する。
//
//  ② 役割分担
//    - ViewModel（このファイル）: 状態・タイマー・判定・指示列生成・シール付与
//    - View (JankenView)       : 状態を表示し、手のタップを ViewModel へ渡す
//    - JankenResultView        : 終了後のタイム・正解率・新記録を表示する
//
//  ★ 調整ポイント（private enum C）★
//   penaltySec    … ミス時に加算するペナルティ秒数
//   flashDuration … 正解/不正解フラッシュの表示時間
//   phaseDuration … フェーズ切替テロップの表示時間（挑戦モードのみ）
//   timerInterval … 経過時間タイマーの更新間隔
//   （この「private enum C に数値を集約する」パターンの解説は GameViewModel.swift 参照）
//
//  ★ @Observable の解説は AppSettings.swift 冒頭を参照 ★
//  ★ タイマー内クロージャの [weak self] の解説は GameViewModel.swift 参照 ★

import SwiftUI

// MARK: - JankenDifficulty（難易度）

/// ゲームの難易度。出題内容・手数・シール倍率を決定する。
enum JankenDifficulty {
    case easy       // かんたん：10回勝て
    case hard       // むずかしい：10回負けろ
    case challenge  // 挑戦：勝て×10→負けろ×10→交互×10

    /// この難易度の総手数（プログレスや指示列の長さに使う）
    var totalRounds: Int {
        switch self {
        case .easy, .hard: return 10
        case .challenge:   return 30
        }
    }

    /// クリア時に獲得するシール枚数の倍率（難しいほど多く貰える）
    var stickerMultiplier: Int {
        switch self {
        case .easy:      return 1  // ← 変更可
        case .hard:      return 2  // ← 変更可
        case .challenge: return 3  // ← 変更可
        }
    }

    /// ベストタイムの保存に使う UserDefaults キー（難易度ごとに別管理）
    var bestTimeKey: String {
        switch self {
        case .easy:      return UDKey.jankenBestTimeEasy
        case .hard:      return UDKey.jankenBestTimeHard
        case .challenge: return UDKey.jankenBestTimeChallenge
        }
    }

    /// 画面表示用のローカライズキー（15言語に翻訳される）
    var labelKey: LocalizedStringKey {
        switch self {
        case .easy:      return "janken_difficulty_easy"
        case .hard:      return "janken_difficulty_hard"
        case .challenge: return "janken_difficulty_challenge"
        }
    }
}

// MARK: - JankenHand（手）

/// じゃんけんの手。emoji・勝敗判定を持つ。
/// ★ CaseIterable の解説は CoinDropViewModel.swift（CoinType）を参照 ★
enum JankenHand: CaseIterable {
    case rock, scissors, paper

    /// 画面に表示する手の絵文字
    var emoji: String {
        switch self {
        case .rock:     return "✊"
        case .scissors: return "✌️"
        case .paper:    return "🖐️"
        }
    }

    /// selfがotherに勝つか（あいこはfalse）
    /// タプルで (自分の手, 相手の手) を一気にパターンマッチして判定する。
    func beats(_ other: JankenHand) -> Bool {
        switch (self, other) {
        case (.rock, .scissors), (.scissors, .paper), (.paper, .rock): return true
        default: return false
        }
    }
}

// MARK: - JankenInstruction（指示）

/// 現在の指示。勝て／負けろを表す。
enum JankenInstruction {
    case win   // 勝て
    case lose  // 負けろ
}

// MARK: - JankenViewModel
//
// ゲームの状態とロジックを一元管理するクラス。
// View はこのクラスのプロパティを表示するだけで、値を変える処理はすべてここに集まる。
//
// ★ @Observable の解説は AppSettings.swift 冒頭を参照 ★

@Observable
final class JankenViewModel {

    // MARK: - ⚙️ 調整パラメータ（ここだけ触ればOK）
    //
    // ゲームの手触りを決める数値を private enum C に集約している。
    // （この集約パターンそのものの解説は GameViewModel.swift 参照）

    private enum C {
        static let penaltySec:     Double = 5.0   // ← 変更可：ミス時のペナルティ秒数
        static let flashDuration:  Double = 0.25  // ← 変更可：フラッシュ表示時間（秒）
        static let phaseDuration:  Double = 2.0   // ← 変更可：フェーズ切替テロップ表示時間（秒）
        static let timerInterval:  Double = 0.05  // ← 変更可：経過時間タイマーの更新間隔（秒）
        static let countdownTotal: Int    = 5     // ← 変更可：カウントダウン総秒数
    }

    // MARK: - 入れ子の型（Phase / Flash）

    /// ゲームの状態。Viewの表示切り替えに使う。
    /// ★ enum に Equatable を付けると、各 case（関連値含む）の一致比較が自動生成される ★
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

    // MARK: - 表示状態（@Observable で View に反映される）
    //
    // ここの var はすべて監視対象。値が変わると参照している View が自動で再描画される。

    /// 現在の画面状態（待機 / カウントダウン / 切替 / プレイ中 / 終了）
    var phase:              Phase             = .idle
    /// 選択中の難易度
    var difficulty:         JankenDifficulty  = .easy
    /// 現在のCPUの手（プレイヤーはこれに勝つ／負ける手を出す）
    var cpuHand:            JankenHand        = .rock
    /// 現在の指示（勝て／負けろ）
    var currentInstruction: JankenInstruction = .win
    var currentRound:       Int              = 0      // 完了済み手数（次の手のindexを兼ねる）
    var missCount:          Int              = 0
    /// 経過時間（秒）。ミス時はペナルティ秒が加算される。
    var elapsed:            TimeInterval     = 0.0
    /// 正解/不正解フラッシュ（nil=非表示）
    var flash:              Flash?           = nil
    /// タップされた手。ボタンの色変化トリガーとして使う。flashと同じタイミングでクリアされる。
    var tappedHand:         JankenHand?      = nil
    /// 今回のプレイで自己ベストを更新したか
    var isNewBest:          Bool             = false

    // MARK: - 計算プロパティ（状態から導出）

    /// この難易度の総手数（difficulty から導出）
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

    /// 難易度ごとのベストタイム（記録なしはnil）。ScoreBoard 経由で読み取る。
    var bestTime: TimeInterval? {
        ScoreBoard.bestTime(for: difficulty.bestTimeKey)
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

    // MARK: - 内部状態（非公開）

    /// 生成済みの指示列。currentRound 番目を順に出題していく。
    private var instructions:   [JankenInstruction] = []
    /// 経過時間タイマー
    private var gameTimer:      Timer?               = nil
    /// 開始前カウントダウン用タイマー
    private var countdownTimer: Timer?               = nil
    /// 経過タイマーを進めてよいか（フェーズ切替中は止める）
    private var isTimerRunning: Bool                 = false
    /// 連打防止ロック（フラッシュ表示中は次のタップを受け付けない）
    private var isTapLocked:    Bool                 = false

    // MARK: - 公開API

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
        // ★ 即時実行クロージャ {...}() で「判定結果の Bool」をその場で計算して isCorrect に入れている
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
            // ミスはタイムにペナルティ秒を直接加算する（＝遅いほど不利になる）
            flash     = .wrong
            elapsed  += C.penaltySec
            missCount += 1
            SoundManager.shared.playWrong()
        }

        currentRound += 1

        let isDone       = currentRound >= totalRounds
        // 挑戦モードで10手目・20手目を終えた瞬間はフェーズ切替テロップを挟む
        let isTransition = difficulty == .challenge
                           && (currentRound == 10 || currentRound == 20)

        // 通常ケース：次の問題を即座にセット（フラッシュと同時に表示）
        if !isDone && !isTransition {
            nextRound()
        }

        // フラッシュ終了後の後処理
        // ★ [weak self] でタイマー/遅延クロージャの循環参照を防ぐ（解説は GameViewModel.swift 参照）
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

    // MARK: - カウントダウン

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

    // MARK: - プレイ開始・経過タイマー

    /// 最初の問題をセットしてプレイ状態に入り、経過タイマーを回し始める
    private func beginPlaying() {
        nextRound()  // 最初の問題をセット
        phase = .playing
        startElapsedTimer()
    }

    /// 経過時間タイマーを開始する。
    /// ★ このゲームの計時方式 ★
    ///   timerInterval ごとに elapsed へ間隔を「加算」していく素朴な方式。
    ///   実時間との微小な誤差は許容し、代わりにミスのペナルティ秒を
    ///   elapsed に直接足せる手軽さを取っている。
    ///   （より正確な「基準時刻からの差分」方式は GameViewModel.swift を参照）
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

    // MARK: - フェーズ切替（挑戦モードのみ）

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

    // MARK: - 終了処理

    /// ゲーム終了。タイマーを止め、ベストタイム更新判定とシール付与を行う。
    private func endGame() {
        gameTimer?.invalidate()
        gameTimer      = nil
        isTimerRunning = false
        // 現在タイムが過去最速なら ScoreBoard が保存し true を返す
        isNewBest      = ScoreBoard.saveIfFaster(time: elapsed, for: difficulty.bestTimeKey)
        awardStickers()
        SoundManager.shared.playTenClear()
        withAnimation(.easeInOut(duration: 0.3)) {
            phase = .finished
        }
    }

    // MARK: - シール報酬

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

    // MARK: - 指示列の生成

    /// 難易度に応じた指示列を生成する
    /// easy=勝て×10 / hard=負けろ×10 / challenge=勝て×10→負けろ×10→交互×10
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

    // MARK: - 時間フォーマット

    /// 秒数を mm:ss.cc（分:秒.1/100秒）の文字列に整形する
    private func formatTime(_ t: TimeInterval) -> String {
        let m  = Int(t) / 60
        let s  = Int(t) % 60
        let cs = Int((t - Double(Int(t))) * 100)
        return String(format: "%02d:%02d.%02d", m, s, cs)
    }
}
