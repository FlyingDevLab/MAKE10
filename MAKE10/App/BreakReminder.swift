//
//  BreakReminder.swift
//  FDL-TenBlitz
//
//  Created by 空飛ぶ研究室(FlyingDevLab) on 2026/10/04.
//
//  続けて遊んでいる時間を数え、一定時間（30分）を超えたら「ひとやすみ しよう」のカードを出す係。
//  ゲームの途中で割り込まないよう、出してよいのは「ゲームの合間」だけにしている。
//    ・タイトル画面にいるとき（MakeTenContentView が確かめる）
//    ・ゲームの結果画面で、エネルギーの数え上げが終わったとき（EnergyRewardBanner が確かめる）
//
//  役割分担:
//    - BreakReminder（このファイル）: 続けて遊んだ時間の計測と、カードを出すかどうかの判断
//    - BreakReminderView            : カードの見た目
//    - MakeTenContentView           : isShowing を見てカードを重ねて出す
//    - AppSettings.isBreakReminderOn: 保護者がオフにできる設定
//
//  ★ 「続けて」の数え方 ★
//    アプリを開いてからの時間を数える。ホーム画面に戻る・別のアプリに切り替える・画面をロックするなど、
//    アプリが裏に回ったら、戻ってきたときに 0 から数え直す（猶予はなし）。
//    通知センターやコントロールセンターを引き出しただけでは裏に回らないので、数え直さない。
//    カードを閉じたときも 0 から数え直すので、遊び続ければ次の30分後にまた出る。

import Foundation

// MARK: - ⚙️ 調整パラメータ

enum BreakReminderTuning {
    /// 休憩をうながすまでの、続けて遊んだ時間（秒）。
    static let playLimit: TimeInterval = 30 * 60   // ← 変更可（30分）
}

// MARK: - BreakReminder

// @Observable / シングルトンの解説は AppSettings.swift 冒頭を参照
@Observable
final class BreakReminder {

    static let shared = BreakReminder()

    /// カードを出しているか。MakeTenContentView がこれを見て重ねて出す。
    private(set) var isShowing = false

    /// 設定パネルを開いているか。開いているあいだはカードを出さない（SharedFrame が知らせる）。
    /// 保護者が設定を触っている最中に、カードが設定の上へ重なって出てこないようにするため。
    @ObservationIgnored var isSettingsOpen = false

    /// 数え始めた時刻。
    @ObservationIgnored private var startedAt = Date()

    private init() {}

    /// カードに出す「◯ぷん あそんだよ」の分数。
    var limitMinutes: Int { Int(BreakReminderTuning.playLimit / 60) }

    /// 休憩の時間になっていて、設定がオンなら、カードを出す。
    /// 「ゲームの合間」にいる側（タイトル画面・結果画面）から呼ぶ。
    func showIfDue(now: Date = Date()) {
        guard AppSettings.shared.isBreakReminderOn,
              !isShowing,
              !isSettingsOpen,
              now.timeIntervalSince(startedAt) >= BreakReminderTuning.playLimit else { return }
        isShowing = true
    }

    /// カードを閉じる。ここからまた数え直す。
    func close(now: Date = Date()) {
        isShowing = false
        startedAt = now
    }

    /// アプリに戻ってきたときに呼ぶ。裏に回っていたので 0 から数え直す。
    func didReturn(now: Date = Date()) {
        startedAt = now
    }
}
