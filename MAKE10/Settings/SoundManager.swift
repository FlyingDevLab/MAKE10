//
//  SoundManager.swift
//  FDL-TenBlitz
//
//  Created by 空飛ぶ研究室(FlyingDevLab) on 2026/03/08.
//

// 効果音・ハプティクス（バイブ）を一括管理するシングルトン。
// 各所から SoundManager.shared.playXxx() を呼ぶだけで再生でき、
// AppSettings.isSoundOn が false のときは play / vibrate の両方が自動的にスキップされる。
//
// シングルトンパターンの解説は AppSettings.swift 冒頭を参照。
//
// ★ 音源ファイルについて ★
//   Sounds/ フォルダに MP3 ファイルを配置することで、
//   iOS 内蔵のシステムサウンドの代わりにカスタム効果音を再生します。
//   ファイルが存在しない場合はシステムサウンド（番号指定）にフォールバックするため、
//   ファイルが揃っていなくてもクラッシュしません。
//   音源ファイルの詳細は docs/SOUND_ASSETS.md を参照してください。
//
// ★ AVAudioPlayer とは？ ★
//   iOS 標準の音声再生クラスです。MP3・WAV などのファイルを再生できます。
//   再生前に prepareToPlay() を呼んでおくと、初回再生時の遅延（レイテンシ）を
//   抑えることができます。
//
// ★ パフォーマンス上の注意（ピンボール対応） ★
//   ピンボールの効果音は SpriteKit の物理接触コールバック（didBegin）から
//   呼ばれる。ここはメインスレッドのフレーム処理の真っ只中で、しかも
//   バンパー連打時は1フレームに複数回発火することがある。
//   そのため本クラスでは以下の対策を入れている:
//     1. 同一音のクールダウン（0.06秒以内の再呼び出しはスキップ）
//     2. 再生中のプレイヤーにだけ頭出し（currentTime = 0）を行う
//        （停止中のプレイヤーへの不要なシーク処理を避ける）
//     3. AVAudioSession を init で一度だけ設定
//        （初回 play() 時に暗黙のセッション起動が走るのを防ぐ）

import UIKit
import AudioToolbox
import AVFoundation
import QuartzCore   // CACurrentMediaTime()（クールダウン計測用の単調時計）

// MARK: - SoundManager

final class SoundManager {

    // MARK: シングルトン

    /// アプリ内どこからでも同一インスタンスにアクセスできるよう、シングルトンとして公開する。
    static let shared = SoundManager()

    // MARK: ハプティクス

    // ★ UIImpactFeedbackGenerator とは？ ★
    //   「コツン」という物理的な手応えを再現するハプティクス（触覚フィードバック）の
    //   生成器です。style で振動の強さを選べます（.light / .medium / .heavy など）。
    //   子ども向けに刺激が強すぎないよう、最も軽い .light を選んでいます。

    /// ハプティクス（バイブ）用のフィードバックジェネレーター。.light スタイルで軽めの振動。
    private let impactGenerator = UIImpactFeedbackGenerator(style: .light)

    // MARK: 音声プレーヤーキャッシュ

    // ★ キャッシュとは？ ★
    //   一度読み込んだデータを手元に保持しておくことです。
    //   効果音は頻繁に再生されるため、毎回ファイルを読み込むのではなく
    //   あらかじめ AVAudioPlayer を生成して辞書に入れておきます。
    //   こうすることで、再生時の遅延をなくすことができます。

    /// ファイル名（拡張子なし）→ AVAudioPlayer のキャッシュ。init でプリロードする。
    private var players: [String: AVAudioPlayer] = [:]

    // MARK: クールダウン

    // ★ クールダウンとは？ ★
    //   同じ音が極端に短い間隔で連続要求されたとき、2回目以降をスキップする仕組み。
    //   ピンボールでは物理接触が1フレームに複数回発生することがあり、そのたびに
    //   MP3 の頭出し（シーク処理）を行うとフレーム落ちの原因になる。
    //   0.06秒は「人間の操作では連打できないが、物理の多重発火は確実に遮断できる」長さ。
    //   聴感上も同じ音が団子にならず、むしろ自然に聞こえる。

    /// 同一音の再生を抑制する最小間隔（秒）。
    private let cooldownInterval: TimeInterval = 0.06

    /// ファイル名 → 最後に再生した時刻。CACurrentMediaTime() ベースの単調時計で記録する。
    /// （Date() と違い、端末の時刻変更やスリープ復帰の影響を受けにくい）
    private var lastPlayed: [String: TimeInterval] = [:]

    // MARK: 初期化

    /// 外部からのインスタンス化を禁止する（シングルトンの「1つだけ」を保証）。
    /// init でオーディオセッションの設定・ハプティクスの準備・音声ファイルのプリロードを行う。
    private init() {
        setupAudioSession()
        impactGenerator.prepare()
        preloadPlayers()
    }

    // MARK: オーディオセッション

    // ★ AVAudioSession とは？ ★
    //   アプリの「音の振る舞い」を OS に宣言する仕組み。未設定のまま play() すると
    //   初回再生時に暗黙のセッション起動が走り、プレイ開始直後の引っかかりの原因になる。
    //   ここで明示的に一度だけ設定しておくことで、そのコストを起動時に前倒しする。
    //
    // ★ .ambient カテゴリを選んだ理由 ★
    //   - マナースイッチ（消音スイッチ）を尊重する（サイレント時は鳴らない）
    //   - 他アプリの音楽（BGM）を止めずに共存できる
    //   子どもが音楽を聴きながら遊んでいても邪魔をしない、本アプリの方針に合う選択。

    /// オーディオセッションを .ambient で一度だけ設定する。失敗しても警告のみでクラッシュさせない。
    private func setupAudioSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.ambient)
            try session.setActive(true)
        } catch {
            print("⚠️ SoundManager: AVAudioSession の設定に失敗しました: \(error)")
        }
    }

    // MARK: プリロード

    /// Sounds/ フォルダ内の MP3 ファイルをすべて読み込み、players に格納する。
    /// ファイルが存在しない場合はスキップする（フォールバックはシステムサウンドが担う）。
    private func preloadPlayers() {

        // プリロードするファイル名の一覧（拡張子なし）。  // ← 音源追加時はここに足す
        let names = [
            "tap", "correct", "wrong", "combo",
            "gameover", "clear", "special", "unlock",
            "coin_land", "coin_merge", "dollar",
            "maze_shot", "maze_hit", "maze_cheese",
            "maze_clear", "maze_damage", "maze_gameover",
            "bumper_hit", "sling_hit", "target_hit", "ball_drain"
        ]

        for name in names {
            // Bundle.main はアプリ本体のパッケージを指す。
            // Sounds/ は Xcode のグループ（黄色フォルダ）のため、ビルド時にファイルは
            // バンドル直下へフラット化される。subdirectory: "Sounds" を指定すると
            // 取得に失敗するので、あえて指定しない（詳細は docs/SOUND_ASSETS.md 参照）。
            guard let url = Bundle.main.url(
                forResource: name,
                withExtension: "mp3"
            ) else {
                // ファイルが見つからなくても警告だけ出してスキップする。
                // クラッシュさせないことが重要。
                print("⚠️ SoundManager: \(name).mp3 が見つかりません（フォールバックします）")
                continue
            }

            do {
                let player = try AVAudioPlayer(contentsOf: url)
                player.prepareToPlay()   // 初回再生のレイテンシを低減する
                players[name] = player
            } catch {
                print("⚠️ SoundManager: \(name).mp3 の読み込みに失敗しました: \(error)")
            }
        }
    }

    // MARK: 再生の共通処理

    /// MP3 ファイルを再生する内部メソッド。
    /// ファイルが players に存在しない場合は fallback のシステムサウンドを鳴らす。
    /// isSoundOn が false のときはどちらも無音にする。
    /// 同一音がクールダウン間隔（0.06秒）以内に再要求された場合はスキップする。
    private func playFile(_ name: String, fallback: SystemSoundID) {
        guard AppSettings.shared.isSoundOn else { return }

        // ── クールダウン判定 ──────────────────────────────────
        // 物理接触の多重発火（1フレームに複数回）による無駄な再生処理を遮断する。
        let now = CACurrentMediaTime()
        if let last = lastPlayed[name], now - last < cooldownInterval {
            return
        }
        lastPlayed[name] = now

        if let player = players[name] {
            // 前の再生が終わっていない場合だけ頭に戻してから再生する。
            // （停止中のプレイヤーは既に先頭にいるため、シーク処理そのものを省ける。
            //   currentTime への代入は再生中だと内部でデコード位置の巻き戻しが走り、
            //   メインスレッドのフレーム処理を圧迫することがある）
            if player.isPlaying {
                player.currentTime = 0
            }
            player.play()
        } else {
            // ファイルが存在しないときはシステムサウンドで代替する。
            AudioServicesPlaySystemSound(fallback)
        }
    }

    /// ハプティクス（バイブ）を鳴らす。playFile() と同様に isSoundOn で無効化できる。
    /// タイル選択・ボタンタップ・正誤フィードバックで呼ばれる。
    func vibrate() {
        guard AppSettings.shared.isSoundOn else { return }
        impactGenerator.impactOccurred()
    }

    // MARK: 効果音（各ゲームから呼ぶ公開メソッド）

    // 第1引数はSounds/フォルダのファイル名（拡張子なし）。
    // fallback はファイルが存在しないときに鳴らすシステムサウンドID。
    // 音源を差し替えたいときはファイルを入れ替えるだけでよい。コード変更不要。

    func playTap()      { playFile("tap",      fallback: 1104) }  // タップ音
    func playCorrect()  { playFile("correct",  fallback: 1000) }  // 正解
    func playWrong()    { playFile("wrong",    fallback: 1053) }  // 不正解
    func playCombo5()   { playFile("combo",    fallback: 1025) }  // 5コンボ
    func playGameOver() { playFile("gameover", fallback: 1010) }  // ゲーム終了
    func playTenClear() { playFile("clear",    fallback: 1022) }  // 好成績クリア
    func playSpecial()  { playFile("special",  fallback: 1021) }  // 特別演出
    func playUnlock()   { playFile("unlock",   fallback: 1016) }  // アンロック

    // MARK: 効果音（CoinDrop専用）

    func playCoinLand()   { playFile("coin_land",  fallback: 1104) }  // コイン着地
    func playCoinMerge()  { playFile("coin_merge", fallback: 1057) }  // 合体
    func playDollarMade() { playFile("dollar",     fallback: 1025) }  // $1完成

    // MARK: 効果音（迷路 Cheese Quest 専用）

    // 迷路ゲームの6イベント専用音。maze_ 接頭辞で他ゲームと区別する。
    // ★ 発射音と撃破音を別ファイルにしている理由 ★
    //   同じ AVAudioPlayer は再生のたびに頭出しされるため、同一音を連打すると前の音が切れる。
    //   別ファイル＝別プレーヤーなら、発射（maze_shot）と撃破（maze_hit）を同フレームで
    //   重ねても互いに切れず、「シュッ＋ポン」と鳴らせる。
    func playMazeShot()     { playFile("maze_shot",     fallback: 1104) }  // 衝撃波発射
    func playMazeHit()      { playFile("maze_hit",      fallback: 1057) }  // 敵撃破（発射音に重ねる）
    func playMazeCheese()   { playFile("maze_cheese",   fallback: 1103) }  // チーズ獲得
    func playMazeClear()    { playFile("maze_clear",    fallback: 1025) }  // ステージクリア
    func playMazeDamage()   { playFile("maze_damage",   fallback: 1053) }  // 被弾
    func playMazeGameOver() { playFile("maze_gameover", fallback: 1010) }  // ゲームオーバー

    // MARK: 効果音（Pinball専用）

    // ピンボールの衝突・ドレイン専用音。bumper/sling/target は接触判定(didBegin)から、
    // ball_drain はボール落下検出(update内)から呼ぶ。ゲーム終了・新記録は既存の
    // playGameOver() / playUnlock() を再利用する（他ゲームの結果画面と統一するため）。
    // 高頻度発火への対策（クールダウン等）は playFile() 側で一括して行っている。
    func playBumperHit() { playFile("bumper_hit", fallback: 1104) }  // バンパー衝突
    func playSlingHit()  { playFile("sling_hit",  fallback: 1025) }  // スリングショット衝突
    func playTargetHit() { playFile("target_hit", fallback: 1000) }  // ターゲット命中
    func playBallDrain() { playFile("ball_drain", fallback: 1053) }  // ボール落下（毎回鳴る。最後の球は0.7秒後に結果音が重なる）
}
