//
//  ThanksSummaryView.swift
//  FDL-TenBlitz
//
//  Created by 空飛ぶ研究室(FlyingDevLab) on 2026/10/04.
//
//  ありがとう てちょう の「まとめ」のページ。できたミッションの数と、その内訳を見せる。
//    ・期間は「いままで」と「こんげつ」を切り替えられる
//    ・内訳は「ミッションごと」「あいてごと」の2つ。回数の多い順に並べる
//    ・まだ 0回のものは一番下に薄く出す（「まだ やっていない ミッション」が分かるように）
//
//  ★ 引き直しとの関係 ★
//    ミッションは引き直せるので、得意なミッションに自然と偏っていく。
//    その偏りがそのまま「その子らしさ」として見えるのも、このページの楽しみ方の1つ。

import SwiftUI

// MARK: - ThanksSummaryView

struct ThanksSummaryView: View {

    private let store = ThanksNotebookStore.shared

    @State private var period: ThanksNotebookStore.SummaryPeriod = .all

    var body: some View {
        let summary = store.summary(for: period)

        ScrollView {
            VStack(spacing: 16) {
                periodPicker
                totalCard(summary)
                // ★ 期間を切り替えたら、内訳はまるごとフェードで入れ替える ★
                //   行ごとに並び替えのアニメーションをさせると、文字や棒が重なって見づらいため。
                VStack(spacing: 16) {
                    section(titleKey: "thanks_summary_by_mission",
                            rows: missionRows(summary))
                    section(titleKey: "thanks_summary_by_person",
                            rows: personRows(summary))
                }
                .id(period)
                .transition(.opacity)
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 24)
        }
    }

    // MARK: 期間の切り替え

    private var periodPicker: some View {
        HStack(spacing: 8) {
            periodButton(.all,       titleKey: "thanks_summary_all")
            periodButton(.thisMonth, titleKey: "thanks_summary_month")
        }
        .padding(4)
        .background(Capsule().fill(Color.black.opacity(0.05)))
    }

    private func periodButton(_ value: ThanksNotebookStore.SummaryPeriod,
                              titleKey: LocalizedStringKey) -> some View {
        Button {
            SoundManager.shared.playTap()
            withAnimation(.easeInOut(duration: 0.25)) { period = value }
        } label: {
            Text(titleKey)
                .font(.system(size: 15, weight: .black, design: .rounded))
                .foregroundStyle(period == value ? DS.textPrimary : DS.muted)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 9)
                .background(Capsule().fill(period == value ? DS.card : Color.clear))
        }
        .buttonStyle(.plain)
    }

    // MARK: 合計

    private func totalCard(_ summary: ThanksNotebookStore.Summary) -> some View {
        VStack(spacing: 6) {
            Text("thanks_summary_total_label")
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(DS.muted)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(verbatim: "💮")
                    .font(.system(size: 36))
                Text("\(summary.total)")
                    .font(.system(size: 48, weight: .black, design: .rounded))
                    .foregroundStyle(DS.energy)
                    .contentTransition(.numericText())
                    .monospacedDigit()
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
        .background(
            RoundedRectangle(cornerRadius: DS.sectionRadius)
                .fill(DS.card)
                .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 3)
        )
    }

    // MARK: 内訳

    /// 内訳の1行分。
    private struct Row: Identifiable {
        let id:      String
        let emoji:   String
        let titleKey: LocalizedStringKey
        let count:   Int
    }

    /// 回数の多い順に並べる。同じ回数どうし（0回を含む）は一覧の順にして、毎回並びが変わらないようにする。
    private func sorted<T>(_ items: [T], count: (T) -> Int) -> [T] {
        items.enumerated()
            .sorted { a, b in
                let ca = count(a.element), cb = count(b.element)
                return ca != cb ? ca > cb : a.offset < b.offset
            }
            .map(\.element)
    }

    private func missionRows(_ summary: ThanksNotebookStore.Summary) -> [Row] {
        sorted(ThanksMission.allCases) { summary.byMission[$0] ?? 0 }
            .map { Row(id: $0.rawValue, emoji: $0.emoji, titleKey: $0.titleKey,
                       count: summary.byMission[$0] ?? 0) }
    }

    private func personRows(_ summary: ThanksNotebookStore.Summary) -> [Row] {
        sorted(ThanksPerson.allCases) { summary.byPerson[$0] ?? 0 }
            .map { Row(id: $0.rawValue, emoji: $0.emoji, titleKey: $0.nameKey,
                       count: summary.byPerson[$0] ?? 0) }
    }

    private func section(titleKey: LocalizedStringKey, rows: [Row]) -> some View {
        let maxCount = max(rows.map(\.count).max() ?? 0, 1)
        return VStack(alignment: .leading, spacing: 10) {
            Text(titleKey)
                .font(.system(size: 17, weight: .black, design: .rounded))
                .foregroundStyle(DS.textPrimary)

            ForEach(rows) { row in
                HStack(spacing: 12) {
                    Text(verbatim: row.emoji)
                        .font(.system(size: 26))
                        .frame(width: 36)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(row.titleKey)
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                            .foregroundStyle(DS.textBody)
                            .fixedSize(horizontal: false, vertical: true)
                        // 回数を棒の長さでも見せる（いちばん多いものが端まで）
                        GeometryReader { geo in
                            Capsule()
                                .fill(DS.energy.opacity(0.75))
                                .frame(width: max(row.count > 0 ? 8 : 0,
                                                  geo.size.width * CGFloat(row.count) / CGFloat(maxCount)))
                        }
                        .frame(height: 8)
                    }
                    Text("thanks_summary_count \(row.count)")
                        .font(.system(size: 16, weight: .black, design: .rounded))
                        .foregroundStyle(row.count > 0 ? DS.energy : DS.muted)
                        .monospacedDigit()
                        .frame(minWidth: 56, alignment: .trailing)
                }
                .opacity(row.count > 0 ? 1 : 0.4)   // まだのものは薄く
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
}
