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
// ★ システムサウンドとは？ ★
//   iOS に最初から内蔵されている短い効果音のことです。
//   それぞれに番号（SystemSoundID）が振られていて、
//   AudioServicesPlaySystemSound(番号) と呼ぶだけで再生できます。
//   音声ファイルをアプリに同梱する必要がないため、
//   このアプリには音声アセットが1つも入っていません（アプリが軽くなる利点もあります）。

import UIKit
import AudioToolbox

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

    // MARK: 初期化

    /// 外部からのインスタンス化を禁止する（シングルトンの「1つだけ」を保証）。
    /// init で prepare() を呼ぶと振動モーターが待機状態になり、
    /// 初回 vibrate() 呼び出し時の遅延（レイテンシ）を低減できる。
    private init() {
        impactGenerator.prepare()
    }

    // MARK: 再生の共通処理

    /// システムサウンドをIDで再生する内部メソッド。
    /// isSoundOn が false のときは即リターンして無音にする。
    /// 公開メソッドはすべてこのメソッドを通じて再生する（消音チェックを1箇所に集約するため）。
    private func play(_ id: SystemSoundID) {
        guard AppSettings.shared.isSoundOn else { return }
        AudioServicesPlaySystemSound(id)
    }

    /// ハプティクス（バイブ）を鳴らす。play() と同様に isSoundOn で無効化できる。
    /// タイル選択・ボタンタップ・正誤フィードバックで呼ばれる。
    func vibrate() {
        guard AppSettings.shared.isSoundOn else { return }
        impactGenerator.impactOccurred()
    }

    // MARK: 効果音（各ゲームから呼ぶ公開メソッド）

    // IDはiOSシステムサウンドの番号で、AudioServicesPlaySystemSoundに直接渡される。
    // IDと音の対応はOS側の事情で変わる可能性があるため、コメントで聴感上の印象を残している。
    // 別の音に差し替えたいときは ID の数字を変えるだけでよい。  // ← 変更可

    func playTap()      { play(1104) }  // タップ音（Tock）
    func playCorrect()  { play(1000) }  // 正解（新着メール音）
    func playWrong()    { play(1053) }  // 不正解（短いブザー音）
    func playCombo5()   { play(1025) }  // 5コンボ（短いチャイム）
    func playGameOver() { play(1010) }  // ゲーム終了（Beep-Beep）
    func playTenClear() { play(1022) }  // 好成績クリア（Anticipate）
    func playSpecial()  { play(1021) }  // 特別演出（Fanfare）
    func playUnlock()   { play(1016) }  // アンロック（Tweet）

    // MARK: 効果音（CoinDrop専用）

    func playCoinLand()   { play(1104) }  // コイン着地（Tock：軽いコツン音）
    func playCoinMerge()  { play(1057) }  // 合体（Tink：チリンとした音）
    func playDollarMade() { play(1025) }  // $1完成（短い派手なチャイム）
}
