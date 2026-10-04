//
//  ThanksNotebookView.swift
//  FDL-TenBlitz
//
//  Created by 空飛ぶ研究室(FlyingDevLab) on 2026/10/04.
//
//  ありがとう てちょう の画面本体。手帳のページ（きょう／カレンダー／まとめ）を切り替える入れ物。
//  手帳の上に付箋が並び、付箋をタップするとページがめくれて入れ替わる。
//
//  ★ このファイルの構成 ★
//    ThanksNotebookTab  … ページ（付箋）の種類
//    ThanksNotebookView … 付箋の列と、めくれるページ
//    StickyNoteTab      … 付箋1枚
//    PageTurn           … ページめくりの見た目（左の綴じ目を軸に回る）
//
//  ★ ページのめくり方 ★
//    右の付箋へ進むとき … いまのページが左の綴じ目を軸にめくれて去り、下から次のページが出る
//    左の付箋へ戻るとき … 前のページが左からめくれて戻ってきて、いまのページの上に重なる
//    本物の手帳と同じく、どちらの向きでも「左の綴じ目」を軸に回す。

import SwiftUI

// MARK: - ThanksNotebookTab

/// 手帳のページ（付箋）。宣言の順に左から並ぶ。
enum ThanksNotebookTab: Int, CaseIterable, Identifiable {
    case today, calendar, summary

    var id: Int { rawValue }

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

    /// 付箋の色。本物の付箋のような、やさしい色にしている。← 変更可
    var noteColor: Color {
        switch self {
        case .today:    return Color(red: 1.00, green: 0.88, blue: 0.45)   // きいろ
        case .calendar: return Color(red: 0.62, green: 0.86, blue: 0.95)   // みずいろ
        case .summary:  return Color(red: 1.00, green: 0.72, blue: 0.78)   // ももいろ
        }
    }

    /// 付箋の傾き（度）。少しずつばらばらにして、手で貼った感じを出す。← 変更可
    var tilt: Double {
        switch self {
        case .today:    return -2.5
        case .calendar: return 1.5
        case .summary:  return -1.0
        }
    }
}

// MARK: - ThanksNotebookView

struct ThanksNotebookView: View {

    /// 開いているページ。
    @State private var tab: ThanksNotebookTab = .today
    /// 次のめくりが「右へ進む」向きか。ページの入れ替えの前に決めておく（selectTab を参照）。
    @State private var turningForward = true
    /// めくっている最中か。めくり終わるまで次の付箋を受け付けない（ページが重なって崩れないように）。
    @State private var isTurning = false

    /// ページめくりの長さ（秒）。← 変更可
    private let turnDuration: Double = 0.55

    /// 手帳の紙の色。アプリの背景より少しだけ白く、クリーム色にしている。← 変更可
    private let paperColor = Color(red: 1.00, green: 0.99, blue: 0.96)

    var body: some View {
        VStack(spacing: 0) {
            noteRow
                .zIndex(1)   // いま開いているページの付箋を、紙の上に重ねて「紙から生えている」ように見せる

            ZStack {
                page(for: tab)
                    .id(tab)
                    .transition(pageTransition)
                    // ★ 重なりの順 ★
                    //   右へ進むときは、去っていく「いまのページ」を上に置いて、めくれて去る様子を見せる。
                    //   左へ戻るときは、戻ってくる「前のページ」を上に置いて、めくれて重なる様子を見せる。
                    //   付箋の番号が小さいページほど上に来るようにすると、どちらの向きでもそうなる。
                    .zIndex(Double(-tab.rawValue))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(
                RoundedRectangle(cornerRadius: DS.cardRadius)
                    .fill(paperColor)
                    .shadow(color: .black.opacity(0.10), radius: 12, x: 0, y: 4)
            )
            .overlay(alignment: .leading) { binding }
            .padding(.horizontal, 12)
            .padding(.bottom, 8)
        }
    }

    // MARK: 付箋

    private var noteRow: some View {
        HStack(alignment: .bottom, spacing: 10) {
            ForEach(ThanksNotebookTab.allCases) { item in
                StickyNoteTab(tab: item, isSelected: item == tab) {
                    selectTab(item)
                }
            }
        }
        .padding(.horizontal, 28)
        .padding(.top, 14)
        // 付箋の下の端を、紙の上の端に少しもぐりこませる
        .padding(.bottom, -10)
    }

    /// 付箋をタップしたとき。向きを先に決めてから、次の瞬間にページを入れ替える。
    ///
    /// ★ 向きの設定とページの入れ替えを分けている理由 ★
    ///   去っていくページのめくり方は、そのページが最後に描かれたときの transition で決まる。
    ///   向きとページを同時に変えると、去るページは古い向きのままめくれてしまう。
    ///   向きだけ先に変えて描き直させ、次の瞬間にページを入れ替えると、正しい向きでめくれる。
    private func selectTab(_ item: ThanksNotebookTab) {
        guard item != tab, !isTurning else { return }
        SoundManager.shared.playTap()
        isTurning = true
        turningForward = item.rawValue > tab.rawValue
        DispatchQueue.main.async {
            withAnimation(.easeInOut(duration: turnDuration)) { tab = item }
            DispatchQueue.main.asyncAfter(deadline: .now() + turnDuration) { isTurning = false }
        }
    }

    // MARK: ページ

    @ViewBuilder
    private func page(for item: ThanksNotebookTab) -> some View {
        Group {
            switch item {
            case .today:    ThanksTodayView()
            case .calendar: ThanksCalendarView()
            case .summary:  ThanksSummaryView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // めくれるあいだも紙として見えるよう、ページごとに紙を敷く
        .background(paperColor)
        .clipShape(RoundedRectangle(cornerRadius: DS.cardRadius))
    }

    /// 向きに応じたページめくり。めくれるのは「上に重なっているページ」だけ。
    private var pageTransition: AnyTransition {
        let turn = AnyTransition.modifier(
            active:   PageTurn(progress: 1),
            identity: PageTurn(progress: 0)
        )
        return turningForward
            ? .asymmetric(insertion: .identity, removal: turn)   // いまのページがめくれて去る
            : .asymmetric(insertion: turn, removal: .identity)   // 前のページがめくれて戻る
    }

    /// 手帳の綴じ目（左の端に並ぶリング）。飾り。
    /// 紙の高さに合わせて、上から下までリングを等間隔に並べる。
    private var binding: some View {
        GeometryReader { geo in
            let gap: CGFloat = 26   // ← 変更可（リングの間隔）
            let count = max(Int((geo.size.height - 40) / gap), 1)
            VStack(spacing: 0) {
                ForEach(0..<count, id: \.self) { _ in
                    Capsule()
                        .fill(DS.muted.opacity(0.35))
                        .frame(width: 14, height: 5)
                        .frame(height: gap)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: 14)
        .offset(x: -6)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

// MARK: - StickyNoteTab

/// 付箋1枚。開いているページの付箋は大きく、紙にくっついて見える。
private struct StickyNoteTab: View {
    let tab:        ThanksNotebookTab
    let isSelected: Bool
    let onTap:      () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 4) {
                Text(verbatim: tab.emoji)
                Text(tab.titleKey)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            .font(.system(size: 15, weight: .black, design: .rounded))
            .foregroundStyle(DS.textPrimary.opacity(isSelected ? 1 : 0.6))
            .frame(maxWidth: .infinity)
            .padding(.top, 10)
            // 開いている付箋は下に長くのびて、紙にもぐりこむ
            .padding(.bottom, isSelected ? 20 : 12)
            .background(
                UnevenRoundedRectangle(topLeadingRadius: 6, bottomLeadingRadius: 0,
                                       bottomTrailingRadius: 0, topTrailingRadius: 6)
                    .fill(tab.noteColor.opacity(isSelected ? 1 : 0.75))
                    .shadow(color: .black.opacity(isSelected ? 0.14 : 0.06), radius: 3, x: 0, y: 2)
            )
            // 開いていない付箋は、少し下がって紙の後ろに隠れ気味にする
            .offset(y: isSelected ? 0 : 6)
            .rotationEffect(.degrees(isSelected ? 0 : tab.tilt), anchor: .bottom)
            .animation(.spring(response: 0.35, dampingFraction: 0.7), value: isSelected)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

// MARK: - PageTurn

/// ページめくりの見た目。左の綴じ目を軸に、紙が手前へ持ち上がって裏返っていく。
/// progress 0 = 平らに開いている、1 = 真横を向いて見えなくなった。
private struct PageTurn: ViewModifier {
    let progress: Double

    func body(content: Content) -> some View {
        content
            // めくれるにつれて紙に影が落ちて見えるよう、少し暗くする
            .overlay(Color.black.opacity(0.18 * progress).allowsHitTesting(false))
            .rotation3DEffect(
                .degrees(-90 * progress),
                axis: (x: 0, y: 1, z: 0),
                anchor: .leading,
                perspective: 0.45
            )
            .opacity(progress > 0.98 ? 0 : 1)
    }
}
