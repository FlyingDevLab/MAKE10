//
//  ThanksNotebookView.swift
//  FDL-TenBlitz
//
//  Created by 空飛ぶ研究室(FlyingDevLab) on 2026/10/04.
//
//  ありがとう てちょう の画面本体。手帳のページ（きょう／カレンダー／まとめ）を切り替える入れ物。
//  付箋の見た目とページめくりの演出は、あとで足す（docs/SPEC_thanks_notebook.md を参照）。

import SwiftUI

// MARK: - ThanksNotebookTab

/// 手帳のページ（タブ）。
enum ThanksNotebookTab: String, CaseIterable, Identifiable {
    case today, calendar, summary

    var id: String { rawValue }

    var emoji: String {
        switch self {
        case .today:    return "✏️"
        case .calendar: return "📅"
        case .summary:  return "🏅"
        }
    }

    var titleKey: LocalizedStringKey {
        switch self {
        case .today:    return "thanks_tab_today"
        case .calendar: return "thanks_tab_calendar"
        case .summary:  return "thanks_tab_summary"
        }
    }
}

// MARK: - ThanksNotebookView

struct ThanksNotebookView: View {

    @State private var tab: ThanksNotebookTab = .today

    var body: some View {
        VStack(spacing: 0) {
            tabBar
            Group {
                switch tab {
                case .today:    ThanksTodayView()
                case .calendar: ThanksCalendarView()
                case .summary:  ThanksSummaryView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var tabBar: some View {
        HStack(spacing: 8) {
            ForEach(ThanksNotebookTab.allCases) { item in
                Button {
                    SoundManager.shared.playTap()
                    tab = item
                } label: {
                    HStack(spacing: 4) {
                        Text(verbatim: item.emoji)
                        Text(item.titleKey)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                    }
                    .font(.system(size: 15, weight: .black, design: .rounded))
                    .foregroundStyle(tab == item ? DS.textPrimary : DS.muted)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: DS.chipRadius)
                            .fill(tab == item ? DS.card : Color.black.opacity(0.04))
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 20)
    }
}
