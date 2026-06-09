//
//  StickerPlayView.swift
//  FDL-TenBlitz
//
//  Created by 空飛ぶ研究室(FlyingDevLab) on 2026/06/04.
//

// シール画面。playStickers を全画面キャンバスに自由配置して遊ぶ。
// 背景色をパステル10色から選択できる。
// StickerStorageView から fullScreenCover で表示される。

import SwiftUI

// MARK: - StickerPlayView

struct StickerPlayView: View {
    @Environment(\.dismiss) private var dismiss
    private let store = StickerStore.shared

    // お絵かき状態（DrawingStore.shared を参照）
    @State private var drawingStore = DrawingStore.shared

    // 現在ドラッグ中のシール ID（nil = 何もドラッグしていない）
    @State private var draggingID: UUID? = nil

    // 選択中の背景色インデックス。起動時に UserDefaults から復元する
    @State private var bgIndex: Int = UserDefaults.standard.integer(forKey: UDKey.playBoardBackground)

    // パレット表示フラグ
    @State private var showPalette: Bool = false

    // MARK: - パステルカラーパレット（10色）
    // インデックスが UDKey.playBoardBackground として保存される
    private let palette: [(name: String, color: Color)] = [
        ("White",     Color(red: 1.00, green: 1.00, blue: 1.00)), // #FFFFFF ← 変更可
        ("Cream",     Color(red: 1.00, green: 0.97, blue: 0.91)), // #FFF8E7 ← 変更可
        ("Pink",      Color(red: 1.00, green: 0.84, blue: 0.88)), // #FFD6E0 ← 変更可
        ("Peach",     Color(red: 1.00, green: 0.90, blue: 0.80)), // #FFE5CC ← 変更可
        ("Yellow",    Color(red: 1.00, green: 0.95, blue: 0.69)), // #FFF3B0 ← 変更可
        ("Green",     Color(red: 0.83, green: 0.96, blue: 0.83)), // #D4F5D4 ← 変更可
        ("Mint",      Color(red: 0.78, green: 0.94, blue: 0.91)), // #C8F0E8 ← 変更可
        ("Blue",      Color(red: 0.78, green: 0.88, blue: 1.00)), // #C8E0FF ← 変更可
        ("Lavender",  Color(red: 0.90, green: 0.83, blue: 1.00)), // #E5D4FF ← 変更可
        ("Gray",      Color(red: 0.91, green: 0.91, blue: 0.94)), // #E8E8F0 ← 変更可
    ]

    // MARK: - Body

    var body: some View {
        ZStack(alignment: .top) {
            // 背景色（全画面）
            palette[bgIndex].color
                .ignoresSafeArea()

            // シールキャンバス
            GeometryReader { geo in
                ZStack {
                    // ★ お絵かきレイヤー（最下層）
                    // 描いた絵がステッカーの下になるよう ZStack の先頭に置く。
                    // お絵かきモード時のみジェスチャーを受け付ける（DrawingCanvasView 内部で制御）。
                    DrawingCanvasView()

                    // ステッカー（お絵かきの上）
                    ForEach(store.playStickers) { sticker in
                        DraggablePlayStickerView(
                            sticker:    sticker,
                            bounds:     geo.size,
                            draggingID: $draggingID
                        )
                        // ★ ステッカーモードのときだけドラッグ可能にする。
                        //   お絵かきモード中は指の動きをすべて DrawingCanvasView に渡す。
                        .allowsHitTesting(drawingStore.canvasMode == .sticker)
                    }
                }
            }
            .coordinateSpace(name: "playBoard")
            .ignoresSafeArea()

            // ヘッダーバー（常に最前面）
            VStack(spacing: 0) {
                headerBar
                    .padding(.top, 52)  // Safe Area 上端からの余白
                Spacer()

                // 背景色パレット（showPalette のとき下から表示）
                if showPalette {
                    paletteBar
                        .padding(.bottom, 10)  // DrawingToolbar との間隔
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }

                // ★ お絵かきツールバー（常時下部固定）
                // モード切替・カラーパレット・消しゴム・全消去を提供する。
                DrawingToolbarView()
                    .padding(.horizontal, 16)
                    .padding(.bottom, 32)  // Safe Area 下端からの余白 ← 変更可
            }
        }
        .ignoresSafeArea()
        .animation(.spring(response: 0.3, dampingFraction: 0.75), value: showPalette)
    }

    // MARK: - Header Bar

    // 戻るボタン・タイトル・パレットボタンを横並びにする。
    // 背景色が何色でも見えるよう、半透明白パネル＋ダーク固定でコントラストを確保する。
    private var headerBar: some View {
        HStack {
            // 戻るボタン
            Button {
                dismiss()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Color(.darkGray))
                    .frame(width: 40, height: 40)
                    .background(
                        Circle().fill(.white.opacity(0.75))
                            .shadow(color: .black.opacity(0.10), radius: 4, x: 0, y: 2)
                    )
            }
            .buttonStyle(.plain)

            Spacer()

            // タイトル
            Text(LocalizedStringKey("game_picker_sticker"))
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundStyle(Color(.darkGray))
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(Capsule().fill(.white.opacity(0.75)))

            Spacer()

            // パレットボタン
            Button {
                withAnimation { showPalette.toggle() }
                SoundManager.shared.vibrate()
            } label: {
                Image(systemName: showPalette ? "paintpalette.fill" : "paintpalette")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(showPalette ? DS.primary : Color(.darkGray))
                    .frame(width: 40, height: 40)
                    .background(
                        Circle().fill(.white.opacity(0.75))
                            .shadow(color: .black.opacity(0.10), radius: 4, x: 0, y: 2)
                    )
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
    }

    // MARK: - Palette Bar

    // 10色のカラーサークルを横並びで表示する。
    // 選択中は枠線と影で強調し、選択後すぐ UserDefaults に保存する。
    private var paletteBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(palette.indices, id: \.self) { i in
                    Button {
                        bgIndex = i
                        UserDefaults.standard.set(i, forKey: UDKey.playBoardBackground)
                        SoundManager.shared.vibrate()
                    } label: {
                        Circle()
                            .fill(palette[i].color)
                            .frame(width: 40, height: 40)
                            .overlay(
                                Circle()
                                    .strokeBorder(
                                        bgIndex == i ? DS.primary : Color(.systemGray4),
                                        lineWidth: bgIndex == i ? 3 : 1.5
                                    )
                            )
                            .shadow(
                                color: bgIndex == i ? DS.primary.opacity(0.35) : .black.opacity(0.08),
                                radius: bgIndex == i ? 6 : 3, x: 0, y: 2
                            )
                            .scaleEffect(bgIndex == i ? 1.15 : 1.0)
                            .animation(.spring(response: 0.2), value: bgIndex)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
        .background(
            RoundedRectangle(cornerRadius: 24)
                .fill(.white.opacity(0.82))
                .shadow(color: .black.opacity(0.10), radius: 10, x: 0, y: -3)
        )
        .padding(.horizontal, 16)
    }
}

// MARK: - DraggablePlayStickerView

// シール画面用のドラッグ可能シール。
// DraggableStickerView（ゲームモード用）と同じ構造だが、
// playStickers / updatePlayPosition / bringPlayToFront を使う点が異なる。
// クランプは全画面（フッター制限なし）。
private struct DraggablePlayStickerView: View {
    let sticker:    StickerStore.Sticker
    let bounds:     CGSize
    @Binding var draggingID: UUID?

    @State private var livePosition: CGPoint? = nil
    @State private var isHeld: Bool = false

    private var isMe: Bool { draggingID == sticker.id }

    private var displayPosition: CGPoint { livePosition ?? storedPosition }
    private var storedPosition: CGPoint {
        CGPoint(x: sticker.xRatio * bounds.width,
                y: sticker.yRatio * bounds.height)
    }

    var body: some View {
        Text(sticker.emoji)
            .font(.system(size: 40))
            .scaleEffect(isHeld ? 1.30 : 1.0)
            .shadow(
                color: isHeld ? .black.opacity(0.20) : .clear,
                radius: 8, x: 0, y: 4
            )
            .animation(.spring(response: 0.22, dampingFraction: 0.55), value: isHeld)
            .position(displayPosition)
            .gesture(
                DragGesture(minimumDistance: 2, coordinateSpace: .named("playBoard"))
                    .onChanged { value in
                        if !isHeld {
                            SoundManager.shared.vibrate()
                            isHeld     = true
                            draggingID = sticker.id
                            StickerStore.shared.bringPlayToFront(id: sticker.id)
                        }
                        livePosition = clamped(value.location)
                    }
                    .onEnded { value in
                        let pos = clamped(value.location)
                        StickerStore.shared.updatePlayPosition(
                            id:     sticker.id,
                            xRatio: pos.x / bounds.width,
                            yRatio: pos.y / bounds.height
                        )
                        livePosition = nil
                        isHeld       = false
                        draggingID   = nil
                    }
            )
    }

    /// 全画面クランプ（上下左右に余白を確保するだけでフッター制限なし）
    private func clamped(_ point: CGPoint) -> CGPoint {
        CGPoint(
            x: max(28, min(bounds.width  - 28, point.x)),
            y: max(80, min(bounds.height - 40, point.y))
        )
    }
}
