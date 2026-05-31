//
//  SoundManager.swift
//  FDL-TenBlitz
//
//  Created by 空飛ぶ研究室(FlyingDevLab) on 2026/03/08.
//
//  効果音・ハプティクスを一括管理するシングルトン。
//  AppSettings.isSoundOn が false の場合はすべて無音になる。

// システムサウンドとハプティクスを一元管理するシングルトン。
// 各所から SoundManager.shared.playXxx() を呼ぶだけで再生でき、
// isSoundOnがfalseのときはplay/vibrateの両方が自動的にスキップされる。

import UIKit
import AudioToolbox

// MARK: - Sound Manager

final class SoundManager {

    // アプリ内どこからでも同一インスタンスにアクセスできるよう、シングルトンとして公開する
    static let shared = SoundManager()

    // ハプティクス（バイブ）用のフィードバックジェネレーター。
    // .lightスタイルで軽めの振動を選択している
    private let impactGenerator = UIImpactFeedbackGenerator(style: .light)

    // 外部からのインスタンス化を禁止する。
    // initでprepare()を呼び、初回vibrate()呼び出し時のレイテンシを低減する
    private init() {
        impactGenerator.prepare()
    }

    // システムサウンドをIDで再生する内部メソッド。
    // isSoundOnがfalseのときは即リターンして無音にする。
    // 公開メソッドはすべてこのメソッドを通じて再生する
    private func play(_ id: SystemSoundID) {
        guard AppSettings.shared.isSoundOn else { return }
        AudioServicesPlaySystemSound(id)
    }

    // ハプティクス（バイブ）を鳴らす。play()と同様にisSoundOnで無効化できる。
    // タイル選択・ボタンタップ・正誤フィードバックで呼ばれる
    func vibrate() {
        guard AppSettings.shared.isSoundOn else { return }
        impactGenerator.impactOccurred()
    }

    // 以下、各シーンで呼ぶ効果音メソッド。
    // IDはiOSシステムサウンドの番号で、AudioServicesPlaySystemSoundに直接渡される。
    // IDと音の対応は変わる可能性があるため、コメントで聴感上の印象を残している。

    func playTap()      { play(1104) }  // タップ音（Tock）
    func playCorrect()  { play(1000) }  // 正解（新着メール音）
    func playWrong()    { play(1053) }  // 不正解（短いブザー音）
    func playCombo5()   { play(1025) }  // 5コンボ（短いチャイム）
    func playGameOver() { play(1010) }  // ゲーム終了（Beep-Beep）
    func playTenClear() { play(1022) }  // 好成績クリア（Anticipate）
    func playSpecial()  { play(1021) }  // 特別演出（Fanfare）
    func playUnlock()   { play(1016) }  // アンロック（Tweet）

    // CoinDrop専用の効果音。
    func playCoinLand()   { play(1104) }  // コイン着地（Tock：軽いコツン音）
    func playCoinMerge()  { play(1057) }  // 合体（Tink：チリンとした音）
    func playDollarMade() { play(1025) }  // $1完成（短い派手なチャイム）
}
