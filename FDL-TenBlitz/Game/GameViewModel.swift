//
//  GameViewModel.swift
//  FDL-TenBlitz
//
//  Created by 空飛ぶ研究室(FlyingDevLab) on 2026/03/08.
//

// MAKE10のゲーム全体を制御するメインViewModel。
// ゲーム状態・タイマー・スコア・コンボ・問題生成・回答処理・Blitzモード解放をすべて管理する。
// UserDefaultsへの永続化もこのクラスが責務を持つ。

import SwiftUI
import Combine

// MARK: - Game View Model

@Observable
final class GameViewModel {

    // MARK: 定数

    private enum C {
        static let answerMarkDuration: Double = 0.5   // 正解/不正解マークの表示時間（秒）
        static let wrongPenalty:       Double = 1.0   // 不正解ペナルティ（秒）
        static let unlockThreshold:    Int    = 100   // Blitzモード解放・ハイスコア解放の正解数閾値
        static let confettiThreshold:  Int    = 10    // 紙吹雪を表示する最低正解数
        static let reactionLimit:      Int    = 15    // 画面上のリアクション絵文字の上限数
        static let stickerPointNormal: Double = 1.1   // normalモードの正解1問あたりのシールポイント
        static let stickerPointBlitz:  Double = 5.6   // blitzモードの正解1問あたりのシールポイント
        static let confettiDuration:   Double = 3.5   // 通常の紙吹雪表示時間（秒）
        static let confettiDurationEx: Double = 5.0   // 100問以上達成時の紙吹雪表示時間（秒）
    }

    // MARK: UserDefaults 永続化
    // didSetで変更のたびにUserDefaultsへ即時書き込む。
    // アプリが強制終了されても最後の状態が保持される。

    // Blitzモード（10秒モード）の解放状態。100問正解で初めてtrueになる
    var isBlitzUnlocked: Bool {
        didSet { UserDefaults.standard.set(isBlitzUnlocked,     forKey: UDKey.isBlitzUnlocked) }
    }
    // Blitzモードのハイスコア表示の解放状態。Blitzで100問正解すると解放される
    var isHighScoreUnlocked: Bool {
        didSet { UserDefaults.standard.set(isHighScoreUnlocked, forKey: UDKey.isHighScoreUnlocked) }
    }
    // Blitzモードの歴代最高スコア
    var blitzHighScore: Int {
        didSet { UserDefaults.standard.set(blitzHighScore,      forKey: UDKey.blitzHighScore) }
    }

    // 問題ごとの出題回数・正解回数（内部統計・ユーザー非公開）
    // インデックスは問題番号（1〜9）に対応。index 0 は使用しない
    private var questionAttempts: [Int] {
        didSet { UserDefaults.standard.set(questionAttempts, forKey: UDKey.questionAttempts) }
    }
    private var questionCorrects: [Int] {
        didSet { UserDefaults.standard.set(questionCorrects, forKey: UDKey.questionCorrects) }
    }

    // MARK: ゲーム中の状態

    var gameState:          GameState   = .title   // 現在の画面状態（タイトル / プレイ中 / 終了）
    var gameMode:           GameMode    = .normal  // 現在のゲームモード（normal=30秒 / blitz=10秒）
    var questionNumber:     Int         = Int.random(in: 1...9)  // 現在の問題（「?+questionNumber=10」）
    var nextQuestionNumber: Int         = 0        // 次の問題（正解後に即座に切り替えるため先読みしておく）
    var tiles:              [Int]       = [1, 2, 3, 4]  // タイル上に表示される4つの数字

    var timeRemaining:    Double      = 30.0       // 残り時間（秒）。0以下でゲーム終了
    var score:            Int         = 0          // 今セッションの正解数
    var combo:            Int         = 0          // 現在の連続正解数。不正解でリセット
    var reactions:        [Reaction]  = []         // コンボ時に表示する浮き上がり絵文字のリスト
    var showConfetti:     Bool        = false       // 10問以上正解したときに紙吹雪を表示するフラグ
    var answerMark:       AnswerMark? = nil         // 正解/不正解のフィードバックアイコン（0.5秒後に消える）
    var showUnlockBanner: Bool        = false       // Blitzモード解放バナーの表示フラグ
    var isNewHighScore:   Bool        = false       // 今回がBlitz歴代最高スコアかどうか

    // タイマーの購読を保持する。停止時にキャンセルするために参照を保持する
    private var timerCancellable: AnyCancellable?

    // 紙吹雪の自動非表示を管理するための世代番号。
    // startGameのたびにインクリメントし、前のゲームのタイマーが誤って紙吹雪を消さないようにする
    private var confettiGeneration:  Int        = 0

    // ゲームモードに応じた制限時間。blitz=10秒、normal=30秒
    var maxTime: Double { gameMode == .blitz ? 10.0 : 30.0 }

    // 残り時間がこの値を下回るとゲージを警告色（赤系）に変える閾値
    var gaugeWarnThreshold: Double { gameMode == .blitz ? 3.0 : 6.0 }

    // コンボ時に画面に浮かぶリアクション絵文字のプール
    private let reactionEmojis = ["❤️","👍","✨","🎉","🌟","😊","👏","🎈","🎂","🎁","🎊"]

    // UserDefaultsから保存済みの値を復元して初期化する。
    // questionAttempts/Correctsは要素数10固定。壊れたデータが保存されていた場合はゼロリセットする
    init() {
        self.isBlitzUnlocked     = UserDefaults.standard.bool(forKey: UDKey.isBlitzUnlocked)
        self.isHighScoreUnlocked = UserDefaults.standard.bool(forKey: UDKey.isHighScoreUnlocked)
        self.blitzHighScore      = UserDefaults.standard.integer(forKey: UDKey.blitzHighScore)
        let savedAttempts = UserDefaults.standard.array(forKey: UDKey.questionAttempts) as? [Int]
        let savedCorrects = UserDefaults.standard.array(forKey: UDKey.questionCorrects) as? [Int]
        // 保存済み配列の要素数が10でない場合（初回起動・データ破損）はゼロ埋め配列で初期化する
        self.questionAttempts = (savedAttempts?.count == 10) ? savedAttempts! : Array(repeating: 0, count: 10)
        self.questionCorrects = (savedCorrects?.count == 10) ? savedCorrects! : Array(repeating: 0, count: 10)
    }

    // MARK: 統計（内部のみ）

    // 問題番号と正誤を内部統計に記録する。
    // 問題番号は1〜9の範囲のみ有効で、範囲外の場合は何もしない
    private func recordAttempt(question: Int, correct: Bool) {
        guard (1...9).contains(question) else { return }
        questionAttempts[question] += 1
        if correct { questionCorrects[question] += 1 }
    }

    // MARK: ゲーム開始

    // 全状態をリセットして新しいゲームを開始する。
    // confettiGenerationをインクリメントして前世代のタイマーを無効化してから、タイマーを新規起動する
    func startGame(mode: GameMode = .normal) {
        gameMode         = mode
        score            = 0
        combo            = 0
        timeRemaining    = maxTime
        reactions        = []
        confettiGeneration  += 1   // 前セッションの紙吹雪タイマーを世代番号で無効化する
        showConfetti         = false
        answerMark       = nil
        isNewHighScore   = false
        showUnlockBanner = false
        gameState        = .playing
        questionNumber     = Int.random(in: 1...9)
        // 次の問題を先読みしておくことで、正解後の問題切り替えを瞬時に行える
        nextQuestionNumber = randomQuestion(excluding: questionNumber)
        tiles              = buildTiles(for: questionNumber)
        startTimer()
    }

    // MARK: タイトルに戻る

    // タイマーを止めてタイトル画面に戻る。answerMarkも消してUIを初期状態にする
    func returnToTitle() {
        stopTimer()
        answerMark = nil
        gameState  = .title
    }

    // MARK: バックグラウンド対応

    // アプリがバックグラウンドに入ったときにタイマーを止める。
    // プレイ中のときのみ動作し、タイトル・結果画面では何もしない
    func suspend() {
        guard gameState == .playing else { return }
        stopTimer()
    }

    // アプリがフォアグラウンドに戻ったときにタイマーを再開する
    func resume() {
        guard gameState == .playing else { return }
        startTimer()
    }

    // MARK: タイマー

    // タイマー計算の基準時刻。startTimer/resetTimerBase呼び出し時に更新される
    private var timerStartDate:     Date?  = nil
    // タイマー開始時点の残り時間。経過時間との差分でtimeRemainingを計算するために保持する
    private var timerBaseRemaining: Double = 0

    // 0.01秒間隔で残り時間を更新するタイマーを開始する。
    // 「開始時刻 + 基準残り時間 - 現在時刻」方式で計算することで、
    // バックグラウンド停止・再開の前後でも正確な残り時間を維持できる
    private func startTimer() {
        timerCancellable?.cancel()
        timerStartDate     = Date()
        timerBaseRemaining = timeRemaining
        timerCancellable   = Timer.publish(every: 0.01, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self, let start = timerStartDate else { return }
                let elapsed = Date().timeIntervalSince(start)
                timeRemaining = max(0.0, timerBaseRemaining - elapsed)
                if timeRemaining <= 0.0 { endGame() }
            }
    }

    // タイマーを停止し、関連する参照をすべてクリアする
    private func stopTimer() {
        timerCancellable?.cancel()
        timerCancellable = nil
        timerStartDate   = nil
    }

    // コンボボーナス時間加算後にタイマーの基準をリセットする。
    // timeRemainingを変更した直後に呼ばないと、次フレームで加算分が打ち消されてしまう
    private func resetTimerBase() {
        timerStartDate     = Date()
        timerBaseRemaining = timeRemaining
    }

    // MARK: 問題生成ヘルパー

    // 直前と同じ問題番号にならないよう、1〜9の中からランダムに次の問題番号を選ぶ
    private func randomQuestion(excluding previous: Int) -> Int {
        var next: Int
        repeat { next = Int.random(in: 1...9) } while next == previous
        return next
    }

    // 問題番号に対して「正解タイル + ランダムなダミー3枚」の計4枚をシャッフルして返す。
    // 正解は必ず「10 - question」で一意に決まる
    private func buildTiles(for question: Int) -> [Int] {
        let correct = 10 - question
        // 正解以外の1〜9からダミーを3つ選ぶ
        let dummies = Array(1...9).filter { $0 != correct }.shuffled().prefix(3)
        return ([correct] + dummies).shuffled()
    }

    // MARK: 回答処理

    // タイルがタップされたときに呼ばれる。正解か不正解かを判定して各ハンドラに振り分ける
    func answer(_ value: Int) {
        if value == 10 - questionNumber {
            handleCorrect()
        } else {
            handleWrong()
        }
    }

    // コンボ中の時間ボーナス量。残り時間が少ないほど多めに加算してカムバックを支援する
    private var comboBonusTime: Double {
        if timeRemaining <= 5.0  { return 1.2 }  // 残り5秒以下：1.2秒加算
        if timeRemaining >= 20.0 { return 0.8 }  // 残り20秒以上：0.8秒加算
        return 1.0                                // それ以外：1.0秒加算
    }

    private func handleCorrect() {
        recordAttempt(question: questionNumber, correct: true)

        score += 1
        combo += 1
        let stickerPt = gameMode == .blitz ? C.stickerPointBlitz : C.stickerPointNormal
        StickerStore.shared.recordCorrect(points: stickerPt)  // 10秒:5.6pt / 30秒:1.1pt
        SoundManager.shared.vibrate()
        SoundManager.shared.playCorrect()

        // 正解マークをanswerMarkDuration秒だけ表示してから消す
        answerMark = .correct
        DispatchQueue.main.asyncAfter(deadline: .now() + C.answerMarkDuration) { [weak self] in
            self?.answerMark = nil
        }

        // コンボ5以上でボーナス時間を加算し、リアクション絵文字を表示する。
        // combo == 5 のときだけ特別なコンボ音を再生する
        if combo >= 5 {
            timeRemaining = min(timeRemaining + comboBonusTime, maxTime)
            resetTimerBase()
            if combo == 5 { SoundManager.shared.playCombo5() }
            addReactions(count: 1)
        }

        // 通常モードで初めて100問正解したときにBlitzモードを解放する
        if gameMode == .normal && score == C.unlockThreshold && !isBlitzUnlocked {
            isBlitzUnlocked  = true
            showUnlockBanner = true
        }

        // 次の問題を先読みしておいた値に即座に切り替える
        questionNumber     = nextQuestionNumber
        nextQuestionNumber = randomQuestion(excluding: questionNumber)
        tiles              = buildTiles(for: questionNumber)
    }

    private func handleWrong() {
        recordAttempt(question: questionNumber, correct: false)

        combo = 0  // 不正解でコンボをリセット
        SoundManager.shared.vibrate()
        SoundManager.shared.playWrong()

        // 不正解マークをanswerMarkDuration秒だけ表示してから消す
        answerMark = .wrong
        DispatchQueue.main.asyncAfter(deadline: .now() + C.answerMarkDuration) { [weak self] in
            self?.answerMark = nil
        }

        // 不正解のペナルティとして残り時間をwrongPenalty秒減らす。
        // 減算後に0以下になったらそのままゲーム終了する
        timeRemaining = max(0, timeRemaining - C.wrongPenalty)
        if timeRemaining <= 0 {
            endGame()
        } else {
            resetTimerBase()
        }
    }

    // MARK: リアクション

    // コンボ達成時に浮き上がる絵文字を追加する。
    // 上限reactionLimit件を超えないよう、追加前に古いものを先頭から削除する
    private func addReactions(count: Int) {
        if reactions.count + count > C.reactionLimit {
            reactions.removeFirst(min(reactions.count, count))
        }
        for _ in 0..<count {
            reactions.append(Reaction(
                emoji:   reactionEmojis.randomElement()!,
                xOffset: .random(in: 16...72)
            ))
        }
    }

    // アニメーション完了後にViewから呼ばれ、表示済みのリアクションを配列から削除する
    func removeReaction(id: UUID) {
        reactions.removeAll { $0.id == id }
    }

    // MARK: ゲーム終了

    // ゲーム終了処理。タイマーを止め、ハイスコア更新・紙吹雪・効果音を処理してから.finishedへ遷移する。
    // 二重呼び出し防止のため、gameState == .playing のときのみ処理する
    private func endGame() {
        guard gameState == .playing else { return }
        stopTimer()
        SoundManager.shared.playGameOver()

        // Blitz解放と同時にゲーム終了した場合は解放音も重ねて再生する
        if showUnlockBanner { SoundManager.shared.playUnlock() }

        // Blitzモード専用の処理：ハイスコア解放判定と更新
        if gameMode == .blitz {
            if score >= C.unlockThreshold && !isHighScoreUnlocked { isHighScoreUnlocked = true }
            if score > blitzHighScore {
                blitzHighScore = score
                isNewHighScore = true
            }
        }

        // confetti閾値以上の正解で紙吹雪を表示する。unlockThreshold以上は特別音と長めの表示時間
        if score >= C.confettiThreshold {
            showConfetti = true
            let isEx = score >= C.unlockThreshold
            isEx ? SoundManager.shared.playSpecial() : SoundManager.shared.playTenClear()
            let duration = isEx ? C.confettiDurationEx : C.confettiDuration
            // confettiGenerationで世代を管理し、古いタイマーが次のゲームの紙吹雪を消さないようにする
            let gen = confettiGeneration
            DispatchQueue.main.asyncAfter(deadline: .now() + duration) { [weak self] in
                guard let self, self.confettiGeneration == gen else { return }
                self.showConfetti = false
            }
        }

        gameState = .finished
    }

    // MARK: リセット

    // ハイスコアのみをリセットする（開発・デバッグ用途を想定）
    func resetHighScore() {
        blitzHighScore = 0
        isNewHighScore = false
    }

    // 全進捗をリセットする（設定画面からの「最初からはじめる」操作）。
    // タイマー停止・紙吹雪停止・フラグ全リセット・統計ゼロクリア・シールデータ削除を行う
    func resetProgress() {
        stopTimer()
        confettiGeneration  += 1   // 実行中の紙吹雪タイマーを世代番号で無効化する
        showConfetti         = false
        isBlitzUnlocked     = false
        isHighScoreUnlocked = false
        blitzHighScore      = 0
        isNewHighScore      = false
        showUnlockBanner    = false
        questionAttempts    = Array(repeating: 0, count: 10)
        questionCorrects    = Array(repeating: 0, count: 10)
        StickerStore.shared.reset()  // シールデータもリセット
        gameState           = .title
    }

    // MARK: 褒め言葉

    // スコアの範囲に応じたローカライズ済みの称賛テキストを返す。
    // FinishedViewが結果カードに表示する。スコアが高いほど派手な表現になる
    var praiseText: LocalizedStringKey {
        switch score {
        case 0:         return "praise_score_0"
        case 1...2:     return "praise_score_1_2"
        case 3...4:     return "praise_score_3_4"
        case 5...9:     return "praise_score_5_9"
        case 10...19:   return "praise_score_10_19"
        case 20...49:   return "praise_score_20_49"
        case 50...99:   return "praise_score_50_99"
        case 100...999: return "praise_score_100_999"
        case 1000...:   return "praise_score_max"
        default:        return "praise_score_0"
        }
    }
}
