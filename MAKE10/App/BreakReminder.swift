//
//  BreakReminder.swift
//  FDL-TenBlitz
//
//  Created by 空飛ぶ研究室(FlyingDevLab) on 2026/10/04.
//
//  続けて遊んでいる時間を数え、一定時間（30分）を超えたら「ひとやすみ しよう」を出すための係。
//  ゲームの途中で割り込まないよう、出すタイミング（タイトル画面に戻ったとき）は MakeTenContentView が決める。
//
//  役割分担:
//    - BreakReminder（このファイル）: 続けて遊んだ時間の計測と「そろそろ休憩？」の判定
//    - BreakReminderView            : 休憩をうながすカードの見た目
//    - MakeTenContentView           : いつ重ねて出し、いつ消すか
//
//  ★ 「続けて」の数え方 ★
//    アプリを開いてからの時間を数える。ホーム画面に戻るなどしてアプリを離れても、
//    すぐ戻ってきたなら続きとして数える。awayResetTime 以上離れていたら、休憩したとみなして 0 から数え直す。
//    カードを閉じたときも 0 から数え直すので、遊び続ければ次の30分後にまた出る。
//    （アプリを終了して開き直した場合も 0 から。保存はしない）

import Foundation

// MARK: - ⚙️ 調整パラメータ

enum BreakReminderTuning {
    /// 休憩をうながすまでの、続けて遊んだ時間（秒）。
    static let playLimit:      TimeInterval = 30 * 60   // ← 変更可（30分）
    /// この時間以上アプリを離れていたら、休憩したとみなして数え直す（秒）。
    static let awayResetTime:  TimeInterval = 5 * 60    // ← 変更可（5分）
}

// MARK: - BreakReminder

final class BreakReminder {

    static let shared = BreakReminder()

    /// 数え始めた時刻。
    private var startedAt = Date()
    /// アプリを離れた時刻。アプリに戻ってきたら nil に戻す。
    private var leftAt: Date? = nil

    private init() {}

    /// 休憩をうながす時間になったか。
    func isDue(now: Date = Date()) -> Bool {
        now.timeIntervalSince(startedAt) >= BreakReminderTuning.playLimit
    }

    /// カードに出す「◯ぷん あそんだよ」の分数。
    var limitMinutes: Int { Int(BreakReminderTuning.playLimit / 60) }

    /// カードを閉じたときに呼ぶ。ここから数え直す。
    func restart(now: Date = Date()) {
        startedAt = now
    }

    /// アプリを離れたとき（バックグラウンドへ移ったとき）に呼ぶ。
    func didLeave(now: Date = Date()) {
        leftAt = now
    }

    /// アプリに戻ってきたときに呼ぶ。長く離れていたら休憩したとみなして数え直す。
    func didReturn(now: Date = Date()) {
        if let leftAt, now.timeIntervalSince(leftAt) >= BreakReminderTuning.awayResetTime {
            startedAt = now
        }
        leftAt = nil
    }
}
