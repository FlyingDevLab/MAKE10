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
//    本物の手帳と同じく、3ページを重ねておき、左の付箋のページほど上に置く。
//    いま開いているページより前（左の付箋）のページは「めくれた状態」で、見えない。
//      右の付箋へ進むとき … いまのページが左の綴じ目を軸にめくれて去り、下から次のページが出る
//      左の付箋へ戻るとき … 前のページが左からめくれて戻ってきて、いまのページの上に重なる
//    開いているページを変えるだけで、あいだのページが自然にめくれる。

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
    /// めくっている最中か。めくり終わるまで次の付箋とページのタップを受け付けない
    /// （付箋をトントンとたたいたとき、2回目がページの行に当たらないように）。
    @State private var isTurning = false

    /// ページめくりの長さ（秒）。← 変更可
    private let turnDuration: Double = 0.55

    /// 手帳の紙の色。アプリの背景より少しだけ白く、クリーム色にしている。← 変更可
    private let paperColor = Color(red: 1.00, green: 0.99, blue: 0.96)

    /// この画面が使える場所の大きさ（回転・分割表示・Duo の開閉のたびに測り直す）。
    @State private var areaSize: CGSize = .zero

    var body: some View {
        VStack(spacing: 0) {
            noteRow
                // ★ 横長の場所でだけ、付箋を少し下げる理由 ★
                //   ヘッダーの下にぶら下がるエネルギー残高（SharedFrame の energyBadge）は画面のまん中に出る。
                //   横長では付箋が横に広がり、まん中の付箋が残高に隠れるので、その分だけ下げる。
                //   ページはスクロールするので、手帳そのものの並べ方は縦長と同じでよい。
                .padding(.top, DS.isWide(areaSize) ? 20 : 0)   // ← 変更可
                .zIndex(1)   // いま開いているページの付箋を、紙の上に重ねて「紙から生えている」ように見せる

            ZStack {
                // ★ 3ページとも置いたままにしている理由 ★
                //   ページを出し入れ（transition）でめくると、去っていくページのめくり方が
                //   「最後に描かれたときの向き」で決まってしまい、向きが変わると動かなくなる。
                //   ページを置いたままにして、めくれ具合（PageTurn の progress）だけを変えれば、
                //   どちらの向きでも毎回同じようにめくれる。
                //   置いたままなので、カレンダーの月やまとめの期間も、ページを行き来しても保たれる。
                ForEach(ThanksNotebookTab.allCases) { item in
                    let isOpen = item == tab
                    page(for: item)
                        // いまのページより前のページは、めくれた状態（見えない）
                        .modifier(PageTurn(progress: item.rawValue < tab.rawValue ? 1 : 0))
                        // ★ 重なりの順 ★ 付箋の番号が小さいページほど上に来る（本物の手帳と同じ）
                        .zIndex(Double(-item.rawValue))
                        .allowsHitTesting(isOpen && !isTurning)
                        .accessibilityHidden(!isOpen)
                }
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
        .onGeometryChange(for: CGSize.self) { proxy in
            proxy.size
        } action: { size in
            areaSize = size
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

    /// 付箋をタップしたとき。開いているページを変えると、あいだのページがめくれる。
    private func selectTab(_ item: ThanksNotebookTab) {
        guard item != tab, !isTurning else { return }
        SoundManager.shared.playTap()
        isTurning = true
        withAnimation(.easeInOut(duration: turnDuration)) {
            tab = item
        } completion: {
            isTurning = false
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

    /// 付箋の形（上の角だけ丸い）。
    private var noteShape: UnevenRoundedRectangle {
        UnevenRoundedRectangle(topLeadingRadius: 6, bottomLeadingRadius: 0,
                               bottomTrailingRadius: 0, topTrailingRadius: 6)
    }

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
                // 開いていない付箋は淡くする。ただし透明にすると、スクロールしたページの文字が
                // 透けて見えるので、白い台紙の上に色を薄く重ねて、透けない淡い色にしている
                noteShape
                    .fill(Color.white)
                    .overlay(noteShape.fill(tab.noteColor.opacity(isSelected ? 1 : 0.75)))
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
///
/// ★ Animatable にしている理由 ★
///   めくれ具合を1コマずつ受け取って描くため。こうしないと、最後に消す（opacity を 0 にする）
///   切り替えが、めくり始めの時点で決まってしまい、ページが回りながら薄くなってしまう。
private struct PageTurn: ViewModifier, Animatable {
    var progress: Double

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

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
