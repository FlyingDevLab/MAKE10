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

import UIKit
import AudioToolbox
import AVFoundation

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

    // MARK: 初期化

    /// 外部からのインスタンス化を禁止する（シングルトンの「1つだけ」を保証）。
    /// init でハプティクスの準備と音声ファイルのプリロードを行う。
    private init() {
        impactGenerator.prepare()
        preloadPlayers()
    }

    // MARK: プリロード

    /// Sounds/ フォルダ内の MP3 ファイルをすべて読み込み、players に格納する。
    /// ファイルが存在しない場合はスキップする（フォールバックはシステムサウンドが担う）。
    private func preloadPlayers() {

        // プリロードするファイル名の一覧（拡張子なし）。  // ← 音源追加時はここに足す
        let names = [
            "tap", "correct", "wrong", "combo",
            "gameover", "clear", "special", "unlock",
            "coin_land", "coin_merge", "dollar"
        ]

        for name in names {
            // Bundle.main はアプリ本体のパッケージを指す。
            // Sounds/ サブフォルダを subdirectory で指定する。
            guard let url = Bundle.main.url(
                forResource: name,
                withExtension: "mp3",
                subdirectory: "Sounds"
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
    private func playFile(_ name: String, fallback: SystemSoundID) {
        guard AppSettings.shared.isSoundOn else { return }

        if let player = players[name] {
            // 前の再生が終わっていない場合は頭に戻してから再生する。
            // （連打されたときに音が重ならないようにする）
            player.currentTime = 0
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
}
