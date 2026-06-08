//
//  GameViewModel.swift
//  FDL-TenBlitz
//
//  Created by 空飛ぶ研究室(FlyingDevLab) on 2026/03/08.
//

// MAKE10のゲーム全体を制御するメインViewModel。
// ゲーム状態・タイマー・スコア・コンボ・問題生成・回答処理・Blitzモード解放をすべて管理する。
// UserDefaultsへの永続化もこのクラスが責務を持つ。
//
// ★ このファイルの全体像 ★
//   MAKE10（30秒 / 10秒 Blitz モード）の頭脳にあたるクラスです。
//   View（画面）は「今の状態を表示するだけ」に徹し、
//   「何が起きたか」「次に何をするか」の判断はすべてここで行います。
//
//   主な責務の一覧:
//     - ゲーム状態の管理（タイトル / プレイ中 / 終了）
//     - タイマーの開始・停止・バックグラウンド対応
//     - 正解・不正解の処理（スコア・コンボ・ペナルティ）
//     - 問題の生成（重複しないランダム選択）
//     - Blitz モードの解放判定
//     - UserDefaults への永続化
//     - シールポイントの付与

import SwiftUI
import Combine

// MARK: - Game View Model

@Observable
final class GameViewModel {

    // MARK: 定数
    //
    // ★ なぜ private enum C にまとめるのか ★
    //   マジックナンバー（コード中に直接書かれた意味不明な数値）を排除するためです。
    //   たとえば "0.5" と書くより "C.answerMarkDuration" と書いた方が
    //   「正解マークの表示時間」であることが一目でわかります。
    //   private にすることでこのクラス内だけで使う定数であることも明示できます。

    private enum C {
        static let answerMarkDuration: Double = 0.5   // 正解/不正解マークの表示時間（秒）
        static let tileAdvanceDelay:   Double = 0.3   // 正解後にタイルを切り替えるまでの遅延（秒）← 変更可
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
    //
    // didSetで変更のたびにUserDefaultsへ即時書き込む。
    // アプリが強制終了されても最後の状態が保持される。
    //
    // ★ なぜ didSet で保存するのか ★
    //   「保存する処理」を呼び出し側のあちこちに書く必要がなくなります。
    //   プロパティの値を変えるだけで自動的に永続化されるため、
    //   「変えたのに保存を忘れた」というバグが構造的に起きません。

    /// Blitzモード（10秒モード）の解放状態。通常モードで100問正解すると true になる
    var isBlitzUnlocked: Bool {
        didSet { UserDefaults.standard.set(isBlitzUnlocked,     forKey: UDKey.isBlitzUnlocked) }
    }

    /// Blitzモードのハイスコア表示の解放状態。Blitzで100問正解すると true になる
    var isHighScoreUnlocked: Bool {
        didSet { UserDefaults.standard.set(isHighScoreUnlocked, forKey: UDKey.isHighScoreUnlocked) }
    }

    /// Blitzモードの歴代最高スコア（正解数）
    var blitzHighScore: Int {
        didSet { UserDefaults.standard.set(blitzHighScore,      forKey: UDKey.blitzHighScore) }
    }

    // 問題ごとの出題回数・正解回数（内部統計・ユーザー非公開）
    // インデックスは問題番号（1〜9）に対応。index 0 は使用しない
    //
    // ★ 要素数10固定の理由 ★
    //   問題番号は 1〜9 の9種類ですが、index 0 を「使わない」として確保することで
    //   questionAttempts[questionNumber] と直接インデックスを使った
    //   直感的なアクセスができます（-1 のオフセット計算が不要）。
    private var questionAttempts: [Int] {
        didSet { UserDefaults.standard.set(questionAttempts, forKey: UDKey.questionAttempts) }
    }
    private var questionCorrects: [Int] {
        didSet { UserDefaults.standard.set(questionCorrects, forKey: UDKey.questionCorrects) }
    }

    // MARK: ゲーム中の状態
    //
    // 以下のプロパティはすべて @Observable により監視対象となっており、
    // 値が変わると参照している View が自動で再描画されます。

    /// 現在の画面状態（.title / .playing / .finished）
    var gameState:          GameState   = .title
    /// 現在のゲームモード（.normal = 30秒 / .blitz = 10秒）
    var gameMode:           GameMode    = .normal
    /// 現在の問題番号（「? + questionNumber = 10」を解く）
    var questionNumber:     Int         = Int.random(in: 1...9)
    /// 次の問題番号（正解後に即座に切り替えるため1問先を先読みしておく）
    var nextQuestionNumber: Int         = 0
    /// タイル上に表示される4つの数字（正解1枚＋ダミー3枚をシャッフル）
    var tiles:              [Int]       = [1, 2, 3, 4]

    /// 残り時間（秒）。0以下でゲーム終了。毎秒ではなく0.01秒間隔で更新される
    var timeRemaining:    Double      = 30.0
    /// 今セッションの正解数（= スコア）
    var score:            Int         = 0
    /// 現在の連続正解数。不正解でリセットされる
    var combo:            Int         = 0
    /// コンボ時に画面上に浮かび上がる絵文字のリスト
    var reactions:        [Reaction]  = []
    /// 10問以上正解したときに紙吹雪を表示するフラグ
    var showConfetti:     Bool        = false
    /// 正解/不正解のフィードバックアイコン。0.5秒後に nil に戻る
    var answerMark:       AnswerMark? = nil
    /// タップされたタイルの数値。フィードバック色の表示に使う。0.5秒後に nil に戻る
    var tappedTileValue:  Int?        = nil
    /// Blitzモード解放バナーの表示フラグ（解放直後のゲーム終了画面で1度だけ表示）
    var showUnlockBanner: Bool        = false
    /// 今回が Blitz 歴代最高スコアかどうか（リザルト画面の「New Record!」表示に使う）
    var isNewHighScore:   Bool        = false

    /// タイマーの購読を保持する変数。stopTimer() 時に cancel() を呼ぶために参照を保持する。
    /// ★ AnyCancellable とは？ ★
    ///   Combine フレームワークの型で、「購読のライフサイクル管理」を担います。
    ///   この変数が nil になる（= cancel() を呼ぶ）とタイマーが止まります。
    private var timerCancellable: AnyCancellable?

    /// 紙吹雪の自動非表示を管理するための世代番号。
    /// startGame のたびにインクリメントし、前のゲームの asyncAfter が
    /// 次のゲームの紙吹雪を誤って消さないようにするための仕組み。
    /// ★ 世代番号パターンとは？ ★
    ///   「タイマーを開始したときの番号」と「タイマーが発火したときの番号」を比較し、
    ///   一致しなければ無効なタイマー（古いゲームのもの）として無視します。
    private var confettiGeneration:  Int        = 0

    /// ゲームモードに応じた制限時間（blitz = 10秒 / normal = 30秒）
    /// ★ 計算プロパティ = 保存せず毎回 gameMode から計算する
    var maxTime: Double { gameMode == .blitz ? 10.0 : 30.0 }

    /// 残り時間がこの値を下回るとゲージを警告色（赤系）に変える閾値
    var gaugeWarnThreshold: Double { gameMode == .blitz ? 3.0 : 6.0 }

    /// コンボ時に画面に浮かぶリアクション絵文字のプール（ランダムに1つ選ばれる）
    private let reactionEmojis = ["❤️","👍","✨","🎉","🌟","😊","👏","🎈","🎂","🎁","🎊"]

    // MARK: 初期化

    /// UserDefaultsから保存済みの値を復元して初期化する。
    /// questionAttempts / Corrects は要素数10固定。
    /// 壊れたデータが保存されていた場合（要素数が10でない）はゼロリセットする。
    init() {
        self.isBlitzUnlocked     = UserDefaults.standard.bool(forKey: UDKey.isBlitzUnlocked)
        self.isHighScoreUnlocked = UserDefaults.standard.bool(forKey: UDKey.isHighScoreUnlocked)
        self.blitzHighScore      = UserDefaults.standard.integer(forKey: UDKey.blitzHighScore)

        // UserDefaults から配列を取り出す。
        // array(forKey:) は Any? を返すため、as? [Int] でキャストしてオプショナルにする
        let savedAttempts = UserDefaults.standard.array(forKey: UDKey.questionAttempts) as? [Int]
        let savedCorrects = UserDefaults.standard.array(forKey: UDKey.questionCorrects) as? [Int]

        // 保存済み配列の要素数が10でない場合（初回起動・データ破損）はゼロ埋め配列で初期化する
        // Array(repeating: 0, count: 10) = [0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
        self.questionAttempts = (savedAttempts?.count == 10) ? savedAttempts! : Array(repeating: 0, count: 10)
        self.questionCorrects = (savedCorrects?.count == 10) ? savedCorrects! : Array(repeating: 0, count: 10)
    }

    // MARK: 統計（内部のみ）

    /// 問題番号と正誤を内部統計に記録する。
    /// 問題番号は 1〜9 の範囲のみ有効で、範囲外の場合は何もしない（安全対策）。
    private func recordAttempt(question: Int, correct: Bool) {
        // contains で範囲チェック。guard で早期リターンして以降のコードをシンプルに保つ
        guard (1...9).contains(question) else { return }
        questionAttempts[question] += 1
        if correct { questionCorrects[question] += 1 }
    }

    // MARK: ゲーム開始

    /// 全状態をリセットして新しいゲームを開始する。
    /// confettiGeneration をインクリメントして前世代のタイマーを無効化してから、
    /// タイマーを新規起動する。
    func startGame(mode: GameMode = .normal) {
        gameMode         = mode
        score            = 0
        combo            = 0
        timeRemaining    = maxTime
        reactions        = []
        confettiGeneration  += 1   // 前セッションの紙吹雪タイマーを世代番号で無効化する
        showConfetti         = false
        answerMark       = nil
        tappedTileValue  = nil     // タイルフィードバック状態をリセット
        isNewHighScore   = false
        showUnlockBanner = false
        gameState        = .playing
        questionNumber     = Int.random(in: 1...9)
        // 次の問題を先読みしておくことで、正解後の問題切り替えを瞬時に行える
        // （正解した瞬間に「次の問題を考える時間」が発生しないようにする）
        nextQuestionNumber = randomQuestion(excluding: questionNumber)
        tiles              = buildTiles(for: questionNumber)
        startTimer()
    }

    // MARK: タイトルに戻る

    /// タイマーを止めてタイトル画面に戻る。answerMark も消して UI を初期状態にする。
    func returnToTitle() {
        stopTimer()
        answerMark      = nil
        tappedTileValue = nil  // タイルフィードバック状態をリセット
        gameState       = .title
    }

    // MARK: バックグラウンド対応

    /// アプリがバックグラウンドに入ったときにタイマーを止める。
    /// プレイ中のときのみ動作し、タイトル・結果画面では何もしない。
    /// ★ バックグラウンドでタイマーを止める理由 ★
    ///   止めなければアプリを切り替えている間も時間が減り続け、
    ///   戻ったらゲームが終わっていた、という体験になってしまいます。
    func suspend() {
        guard gameState == .playing else { return }
        stopTimer()
    }

    /// アプリがフォアグラウンドに戻ったときにタイマーを再開する。
    func resume() {
        guard gameState == .playing else { return }
        startTimer()
    }

    // MARK: タイマー

    /// タイマー計算の基準時刻。startTimer / resetTimerBase 呼び出し時に更新される。
    private var timerStartDate:     Date?  = nil
    /// タイマー開始時点の残り時間。経過時間との差分で timeRemaining を計算するために保持する。
    private var timerBaseRemaining: Double = 0

    /// 0.01秒間隔で残り時間を更新するタイマーを開始する。
    ///
    /// ★ なぜ「開始時刻 + 基準残り時間 - 現在時刻」方式を使うのか ★
    ///   単純に「毎回 0.01 を引く」方式だとタイマー精度のズレが積み重なります。
    ///   また、バックグラウンド停止中はタイマーが止まるため、
    ///   再開後に「止まっていた間の時間」が正しく計算されません。
    ///   現在時刻から経過時間を毎回計算することで、どちらの問題も解決できます。
    private func startTimer() {
        timerCancellable?.cancel()  // 既存のタイマーがあれば先に止める（二重起動防止）
        timerStartDate     = Date()
        timerBaseRemaining = timeRemaining
        // Timer.publish: 指定した間隔でイベントを発火する Combine のパブリッシャー
        // .autoconnect(): subscribe した瞬間に自動で発火を開始する
        // .sink: イベントを受け取るたびにクロージャを実行する
        timerCancellable   = Timer.publish(every: 0.01, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                // [weak self]: 循環参照を防ぐためのキャプチャ方法。
                // self が解放済みでも安全にアクセスできるよう弱参照にする
                guard let self, let start = timerStartDate else { return }
                let elapsed = Date().timeIntervalSince(start)  // 開始からの経過秒数
                timeRemaining = max(0.0, timerBaseRemaining - elapsed)
                if timeRemaining <= 0.0 { endGame() }
            }
    }

    /// タイマーを停止し、関連する参照をすべてクリアする。
    private func stopTimer() {
        timerCancellable?.cancel()  // 発火を止める
        timerCancellable = nil      // 参照を解放してメモリを返す
        timerStartDate   = nil
    }

    /// コンボボーナス時間加算後にタイマーの基準をリセットする。
    /// timeRemaining を変更した直後に呼ばないと、次のタイマー発火で加算分が打ち消されてしまう。
    /// ★ 基準をリセットする理由 ★
    ///   タイマーは「開始時刻からの経過時間」で残り時間を計算しているため、
    ///   timeRemaining だけ変えても「開始時刻」が古いままだと計算がずれます。
    ///   基準を「今この瞬間」にリセットすることで変更後の値から正しく継続できます。
    private func resetTimerBase() {
        timerStartDate     = Date()
        timerBaseRemaining = timeRemaining
    }

    // MARK: 問題生成ヘルパー

    /// 直前と同じ問題番号にならないよう、1〜9 の中からランダムに次の問題番号を選ぶ。
    /// ★ repeat-while とは？ ★
    ///   条件を満たさなければ繰り返す後判定ループです。
    ///   「とりあえず1回実行してから条件チェック」する場合に使います。
    ///   重複するたびに引き直すシンプルな実装で、9種類しかないので無限ループになりません。
    private func randomQuestion(excluding previous: Int) -> Int {
        var next: Int
        repeat { next = Int.random(in: 1...9) } while next == previous
        return next
    }

    /// 問題番号に対して「正解タイル + ランダムなダミー3枚」の計4枚をシャッフルして返す。
    /// 正解は必ず「10 - question」で一意に決まる（例: question = 3 なら正解は 7）。
    private func buildTiles(for question: Int) -> [Int] {
        let correct = 10 - question
        // 正解以外の 1〜9 からダミーを3つランダムに選ぶ
        // .filter で正解を除外 → .shuffled() でランダムに並び替え → .prefix(3) で3枚だけ取る
        let dummies = Array(1...9).filter { $0 != correct }.shuffled().prefix(3)
        // 正解1枚とダミー3枚を合わせて再シャッフルし、順番をランダムにする
        return ([correct] + dummies).shuffled()
    }

    // MARK: 回答処理

    /// タイルがタップされたときに呼ばれる。正解か不正解かを判定して各ハンドラに振り分ける。
    /// フィードバック表示中（tappedTileValue != nil）は二重タップを無視する。
    func answer(_ value: Int) {
        guard tappedTileValue == nil else { return }  // フィードバック表示中は入力を無視
        tappedTileValue = value                        // タップしたタイルを記録（色変化のトリガー）
        if value == 10 - questionNumber {
            handleCorrect()
        } else {
            handleWrong()
        }
    }

    /// コンボ中の時間ボーナス量。残り時間が少ないほど多めに加算してカムバックを支援する。
    /// ★ 残り時間で変える理由 ★
    ///   残り時間が多いときに大きなボーナスを与えると簡単になりすぎるため、
    ///   追い詰められているほど有利になる「カムバック補正」として機能させています。
    private var comboBonusTime: Double {
        if timeRemaining <= 5.0  { return 1.2 }  // 残り5秒以下：1.2秒加算（最大補正）
        if timeRemaining >= 20.0 { return 0.8 }  // 残り20秒以上：0.8秒加算（最小補正）
        return 1.0                                // それ以外：1.0秒加算（標準）
    }

    /// 正解時の処理。スコア・コンボ更新、シールポイント付与、問題の切り替えなどを行う。
    private func handleCorrect() {
        recordAttempt(question: questionNumber, correct: true)

        score += 1
        combo += 1
        // Blitz モードの方が短時間で答えているため、シールポイントを高く設定している
        let stickerPt = gameMode == .blitz ? C.stickerPointBlitz : C.stickerPointNormal
        StickerStore.shared.recordCorrect(points: stickerPt)  // 10秒:5.6pt / 30秒:1.1pt
        SoundManager.shared.vibrate()
        SoundManager.shared.playCorrect()

        // 正解マークを C.answerMarkDuration 秒だけ表示してから消す
        // asyncAfter: 指定秒後にメインスレッドでクロージャを実行する非同期処理
        answerMark = .correct
        DispatchQueue.main.asyncAfter(deadline: .now() + C.answerMarkDuration) { [weak self] in
            self?.answerMark = nil
        }

        // コンボ5以上でボーナス時間を加算し、リアクション絵文字を表示する。
        // combo == 5 のときだけ特別なコンボ音を再生する（最初の5連続のみ特別扱い）
        if combo >= 5 {
            // min(~, maxTime) で制限時間を超えないようにキャップする
            timeRemaining = min(timeRemaining + comboBonusTime, maxTime)
            resetTimerBase()  // 時間を変えたので基準をリセット（忘れると次フレームで戻る）
            if combo == 5 { SoundManager.shared.playCombo5() }
            addReactions(count: 1)
        }

        // 通常モードで初めて100問正解したときに Blitz モードを解放する（1度だけ）
        if gameMode == .normal && score == C.unlockThreshold && !isBlitzUnlocked {
            isBlitzUnlocked  = true
            showUnlockBanner = true
        }

        // 緑フラッシュを見せてから tiles を更新する（C.tileAdvanceDelay 秒後）
        // タイルが変わると tappedTileValue との一致がなくなり、自然にハイライトが消える
        DispatchQueue.main.asyncAfter(deadline: .now() + C.tileAdvanceDelay) { [weak self] in
            self?.advanceTiles()
        }
        // answerMark と同じタイミングで tappedTileValue をクリアする（念のための後始末）
        DispatchQueue.main.asyncAfter(deadline: .now() + C.answerMarkDuration) { [weak self] in
            self?.tappedTileValue = nil
        }
    }

    /// 正解後の問題切り替え処理。
    /// handleCorrect() から直接呼ばず asyncAfter 経由で呼ぶことで遅延を実現する。
    /// 先読みしておいた次の問題に切り替え、さらに次の問題を先読みする。
    private func advanceTiles() {
        tappedTileValue    = nil
        questionNumber     = nextQuestionNumber
        nextQuestionNumber = randomQuestion(excluding: questionNumber)
        tiles              = buildTiles(for: questionNumber)
    }

    /// 不正解時の処理。コンボリセット、ペナルティ（時間減算）、場合によってはゲーム終了。
    private func handleWrong() {
        recordAttempt(question: questionNumber, correct: false)

        combo = 0  // 不正解でコンボをリセット（0に戻すだけで問題は変えない）
        SoundManager.shared.vibrate()
        SoundManager.shared.playWrong()

        // 不正解マークを C.answerMarkDuration 秒だけ表示してから消す
        answerMark = .wrong
        DispatchQueue.main.asyncAfter(deadline: .now() + C.answerMarkDuration) { [weak self] in
            self?.answerMark = nil
        }

        // 不正解のペナルティとして残り時間を C.wrongPenalty 秒減らす。
        // max(0, ...) で 0 秒を下回らないようにする（マイナスになると表示がおかしくなる）
        timeRemaining = max(0, timeRemaining - C.wrongPenalty)
        if timeRemaining <= 0 {
            endGame()          // ペナルティで時間切れになった場合はそのままゲーム終了
        } else {
            resetTimerBase()   // 時間を変えたので基準をリセット
        }

        // answerMark と同じタイミングで tappedTileValue をクリアし、赤ハイライトを消す
        DispatchQueue.main.asyncAfter(deadline: .now() + C.answerMarkDuration) { [weak self] in
            self?.tappedTileValue = nil
        }
    }

    // MARK: リアクション

    /// コンボ達成時に浮き上がる絵文字を追加する。
    /// 上限 C.reactionLimit 件を超えないよう、追加前に古いものを先頭から削除する。
    /// ★ 上限を設ける理由 ★
    ///   コンボが続くと絵文字が無制限に増えてメモリを圧迫するため、
    ///   古いものから削除して一定数以内に収めます。
    private func addReactions(count: Int) {
        if reactions.count + count > C.reactionLimit {
            // 追加予定数だけ先頭から削除する（先入れ先出し = 古い順に消える）
            reactions.removeFirst(min(reactions.count, count))
        }
        for _ in 0..<count {
            reactions.append(Reaction(
                emoji:   reactionEmojis.randomElement()!,  // プールからランダムに1つ選ぶ
                xOffset: .random(in: 16...72)              // 横位置をランダムにしてバラけさせる
            ))
        }
    }

    /// アニメーション完了後に View から呼ばれ、表示済みのリアクションを配列から削除する。
    /// UUID で特定のリアクションだけを消すことで、複数が同時に浮いていても正しく管理できる。
    func removeReaction(id: UUID) {
        reactions.removeAll { $0.id == id }
    }

    // MARK: ゲーム終了

    /// ゲーム終了処理。タイマーを止め、ハイスコア更新・紙吹雪・効果音を処理してから
    /// .finished へ遷移する。
    /// 二重呼び出し防止のため、gameState == .playing のときのみ処理する。
    /// ★ 二重呼び出しが起きうる理由 ★
    ///   タイマーの発火タイミングとペナルティのタイミングが重なると
    ///   endGame() が2回呼ばれる可能性があります。guard で防いでいます。
    private func endGame() {
        guard gameState == .playing else { return }
        stopTimer()
        SoundManager.shared.playGameOver()

        // Blitz 解放と同時にゲーム終了した場合は解放音も重ねて再生する
        if showUnlockBanner { SoundManager.shared.playUnlock() }

        // ── Blitzモード専用の処理 ──────────────────────────
        if gameMode == .blitz {
            // Blitz で100問達成かつ未解放ならハイスコア表示を解放する
            if score >= C.unlockThreshold && !isHighScoreUnlocked { isHighScoreUnlocked = true }
            // 今回のスコアが歴代最高を上回ればハイスコアを更新する
            if score > blitzHighScore {
                blitzHighScore = score
                isNewHighScore = true
            }
        }

        // ── 紙吹雪の処理 ──────────────────────────────────
        // confettiThreshold 以上の正解で紙吹雪を表示する。
        // unlockThreshold 以上は特別音と長めの表示時間で特別感を演出する
        if score >= C.confettiThreshold {
            showConfetti = true
            let isEx = score >= C.unlockThreshold
            isEx ? SoundManager.shared.playSpecial() : SoundManager.shared.playTenClear()
            let duration = isEx ? C.confettiDurationEx : C.confettiDuration

            // 世代番号を保存しておき、発火時に一致しなければ何もしない（古いタイマー対策）
            let gen = confettiGeneration
            DispatchQueue.main.asyncAfter(deadline: .now() + duration) { [weak self] in
                guard let self, self.confettiGeneration == gen else { return }
                self.showConfetti = false
            }
        }

        gameState = .finished
    }

    // MARK: リセット

    /// ハイスコアのみをリセットする（開発・デバッグ用途を想定）。
    func resetHighScore() {
        blitzHighScore = 0
        isNewHighScore = false
    }

    /// 全進捗をリセットする（設定画面からの「最初からはじめる」操作）。
    /// タイマー停止・紙吹雪停止・フラグ全リセット・統計ゼロクリア・シールデータ削除を行う。
    func resetProgress() {
        stopTimer()
        confettiGeneration  += 1   // 実行中の紙吹雪タイマーを世代番号で無効化する
        showConfetti         = false
        isBlitzUnlocked     = false
        isHighScoreUnlocked = false
        blitzHighScore      = 0
        isNewHighScore      = false
        showUnlockBanner    = false
        // Array(repeating:count:) でゼロ埋め配列を作り直して統計をクリア
        questionAttempts    = Array(repeating: 0, count: 10)
        questionCorrects    = Array(repeating: 0, count: 10)
        StickerStore.shared.reset()  // シールデータもリセット（こちらは StickerStore が責任を持つ）
        gameState           = .title
    }

    // MARK: 褒め言葉

    /// スコアの範囲に応じたローカライズ済みの称賛テキストを返す。
    /// FinishedView が結果カードに表示する。スコアが高いほど派手な表現になる。
    /// ★ LocalizedStringKey とは？ ★
    ///   Localizable.xcstrings に登録されたキーを表す型です。
    ///   "praise_score_0" というキーを返すと、SwiftUI が自動で
    ///   端末の言語設定に合った翻訳テキストに変換して表示します。
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
