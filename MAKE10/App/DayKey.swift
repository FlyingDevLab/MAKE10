//
//  DayKey.swift
//  FDL-TenBlitz
//
//  Created by 空飛ぶ研究室(FlyingDevLab) on 2026/10/01.
//
//  「何月何日か」を "2026-10-01" の形の文字列にする小さな道具。
//  シールやさんの品揃えの入れ替えと、ログインボーナスの「その日に初めて開いたか」の判定で共用する。
//  どちらも端末のカレンダー・タイムゾーンの 0時を1日の区切りにしている。

import Foundation

// MARK: - DayKey

// case のない enum を名前空間として使う理由は ScoreBoard.swift を参照
enum DayKey {

    /// 日付を "2026-10-01" の形の文字列にする。
    static func string(for date: Date) -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    /// "2026-10-01" の形の文字列を、その日の 0時の日付に戻す。読めなければ nil。
    /// ありがとう てちょう のカレンダーで、記録のいちばん古い月を求めるのに使う。
    static func date(from key: String) -> Date? {
        let parts = key.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return Calendar.current.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }

    /// 指定した日の前日を "2026-09-30" の形の文字列にする。
    static func previousDay(of date: Date) -> String {
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: date) ?? date
        return string(for: yesterday)
    }
}
