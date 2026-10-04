//
//  ThanksCalendarView.swift
//  FDL-TenBlitz
//
//  Created by 空飛ぶ研究室(FlyingDevLab) on 2026/10/04.
//
//  ありがとう てちょう の「カレンダー」のページ。月ごとの表に、その日にできた数のスタンプを押す。
//  日付をタップすると、その日のミッションと相手が下に出る（見るだけ。チェックは「きょう」のページだけ）。
//
//  ★ このファイルの構成 ★
//    ThanksCalendarView … 月の切り替え・カレンダーの表・選んだ日の中身
//    ThanksStamp        … チェック数に応じたスタンプ（0個＝なし／1〜2個＝🌸／ぜんぶ＝💮）
//
//  ★ 曜日の並びと名前 ★
//    Calendar.current に任せている。日曜はじまり／月曜はじまりや、曜日の短い名前（日・Sun・So など）は
//    端末の言語・地域設定に自動で合わせられるので、翻訳を用意しなくてよい。

import SwiftUI

// MARK: - ThanksCalendarView

struct ThanksCalendarView: View {

    // MARK: 依存

    private let store    = ThanksNotebookStore.shared
    private let calendar = Calendar.current

    // MARK: ローカル状態

    /// 表示している月（その月の1日）。
    @State private var month: Date = Calendar.current.startOfMonth(for: Date())
    /// 選んでいる日。nil のときは中身を出さない。
    @State private var selectedDay: Date? = nil

    // MARK: body

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                monthHeader
                grid
                    .id(month)   // 月が変わったら別の表として入れ替え、横にすべらせる
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .scale(scale: 0.96)),
                        removal:   .opacity
                    ))
                if let day = selectedDay {
                    dayDetail(day)
                        .id(day)
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 24)
        }
        .animation(.easeInOut(duration: 0.25), value: month)
        .animation(.easeInOut(duration: 0.2), value: selectedDay)
    }

    // MARK: 月の切り替え

    private var monthHeader: some View {
        HStack {
            monthButton(systemImage: "chevron.left", enabled: canGoBack) { moveMonth(by: -1) }
            Spacer()
            Text(month, format: .dateTime.year().month(.wide))
                .font(.system(size: 20, weight: .black, design: .rounded))
                .foregroundStyle(DS.textPrimary)
            Spacer()
            monthButton(systemImage: "chevron.right", enabled: canGoForward) { moveMonth(by: 1) }
        }
    }

    private func monthButton(systemImage: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button {
            SoundManager.shared.playTap()
            action()
        } label: {
            Image(systemName: systemImage)
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(enabled ? DS.textPrimary : DS.muted.opacity(0.3))
                .frame(width: 44, height: 44)
                .background(Circle().fill(Color.black.opacity(enabled ? 0.05 : 0.02)))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }

    /// 前の月へ行けるか。記録のいちばん古い月より前には行かない。
    private var canGoBack: Bool { month > earliestMonth }
    /// 次の月へ行けるか。きょうの月より先には行かない。
    private var canGoForward: Bool { month < calendar.startOfMonth(for: Date()) }

    /// 記録のいちばん古い月（記録が無ければきょうの月）。
    private var earliestMonth: Date {
        let thisMonth = calendar.startOfMonth(for: Date())
        let oldest = store.pages.keys.sorted().first.flatMap(DayKey.date(from:))
        return oldest.map { min(calendar.startOfMonth(for: $0), thisMonth) } ?? thisMonth
    }

    private func moveMonth(by value: Int) {
        guard let next = calendar.date(byAdding: .month, value: value, to: month) else { return }
        month = next
        selectedDay = nil
    }

    // MARK: カレンダーの表

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 7)

    private var grid: some View {
        VStack(spacing: 8) {
            // 曜日の見出し。並びは端末の設定（日曜はじまり／月曜はじまり）に合わせる
            LazyVGrid(columns: columns, spacing: 6) {
                ForEach(Array(weekdaySymbols.enumerated()), id: \.offset) { _, symbol in
                    Text(symbol)
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(DS.muted)
                }
            }
            LazyVGrid(columns: columns, spacing: 6) {
                // 1日の前の空きマス
                ForEach(0..<leadingBlanks, id: \.self) { _ in
                    Color.clear.frame(height: 58)
                }
                ForEach(daysInMonth, id: \.self) { day in
                    dayCell(day)
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: DS.sectionRadius)
                .fill(DS.card)
                .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 3)
        )
    }

    /// 日付のマス。番号の下に、その日にできた数のスタンプを押す。
    private func dayCell(_ day: Date) -> some View {
        let page      = store.page(on: day)
        let isToday   = calendar.isDateInToday(day)
        let isFuture  = day > Date() && !isToday
        let selected  = selectedDay.map { calendar.isDate($0, inSameDayAs: day) } ?? false

        return Button {
            SoundManager.shared.playTap()
            selectedDay = selected ? nil : day
        } label: {
            VStack(spacing: 2) {
                Text("\(calendar.component(.day, from: day))")
                    .font(.system(size: 14, weight: isToday ? .black : .bold, design: .rounded))
                    .foregroundStyle(isToday ? DS.energy : DS.textBody)
                ThanksStamp(checkedCount: page?.checkedCount ?? 0,
                            total: page?.missions.count ?? ThanksTuning.missionsPerDay,
                            size: 24)
                    .frame(height: 28)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 58)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(selected ? DS.energy.opacity(0.14) : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(isToday ? DS.energy.opacity(0.6) : Color.clear, lineWidth: 2)
            )
            .opacity(isFuture ? 0.35 : 1)
        }
        .buttonStyle(.plain)
        .disabled(isFuture)
    }

    // MARK: 選んだ日の中身

    private func dayDetail(_ day: Date) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(day, format: .dateTime.month().day().weekday())
                .font(.system(size: 16, weight: .black, design: .rounded))
                .foregroundStyle(DS.textPrimary)

            if let page = store.page(on: day), !page.missions.isEmpty {
                ForEach(page.missions) { mission in
                    HStack(spacing: 12) {
                        Text(verbatim: mission.emoji)
                            .font(.system(size: 28))
                        VStack(alignment: .leading, spacing: 4) {
                            Text(mission.titleKey)
                                .font(.system(size: 15, weight: .bold, design: .rounded))
                                .foregroundStyle(page.isChecked(mission) ? DS.textPrimary : DS.muted)
                                .fixedSize(horizontal: false, vertical: true)
                            if let people = page.checks[mission], !people.isEmpty {
                                Text(verbatim: people.map(\.emoji).joined(separator: " "))
                                    .font(.system(size: 18))
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        Text(verbatim: page.isChecked(mission) ? "💮" : "・")
                            .font(.system(size: page.isChecked(mission) ? 28 : 20))
                            .foregroundStyle(DS.muted.opacity(0.4))
                    }
                    .opacity(page.isChecked(mission) ? 1 : 0.6)
                }
            } else {
                Text("thanks_calendar_empty")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(DS.muted)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: DS.sectionRadius)
                .fill(DS.card)
                .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 3)
        )
    }

    // MARK: 日付の計算

    /// 曜日の短い名前を、端末の週のはじまりに合わせて並べたもの。
    private var weekdaySymbols: [String] {
        let symbols = calendar.veryShortStandaloneWeekdaySymbols   // [日, 月, …] の順
        let first   = calendar.firstWeekday - 1                    // 1 = 日曜
        return Array(symbols[first...] + symbols[..<first])
    }

    /// 1日の前に入れる空きマスの数。
    private var leadingBlanks: Int {
        let weekday = calendar.component(.weekday, from: month)
        return (weekday - calendar.firstWeekday + 7) % 7
    }

    /// 表示している月の日付の一覧。
    private var daysInMonth: [Date] {
        guard let range = calendar.range(of: .day, in: .month, for: month) else { return [] }
        return range.compactMap { calendar.date(byAdding: .day, value: $0 - 1, to: month) }
    }
}

// MARK: - ThanksStamp

/// その日にできた数に応じたスタンプ。0個は何も押さない。全部できた日は花丸。
struct ThanksStamp: View {
    let checkedCount: Int
    let total:        Int
    var size:         CGFloat = 24

    var body: some View {
        if checkedCount == 0 {
            Color.clear.frame(width: size, height: size)
        } else if checkedCount >= total {
            Text(verbatim: "💮")
                .font(.system(size: size))
        } else {
            Text(verbatim: "🌸")
                .font(.system(size: size * 0.75))   // 途中までの日は、花丸より少し小さく
        }
    }
}

// MARK: - 日付のヘルパー

extension Calendar {
    /// その日を含む月の1日（0時）。
    func startOfMonth(for date: Date) -> Date {
        self.date(from: dateComponents([.year, .month], from: date)) ?? startOfDay(for: date)
    }
}
