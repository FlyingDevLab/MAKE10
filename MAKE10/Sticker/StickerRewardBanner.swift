//
//  StickerRewardBanner.swift
//  FDL-TenBlitz
//
//  Created by 空飛ぶ研究室(FlyingDevLab) on 2026/09/15.
//

// 結果画面に埋め込むだけで「シール獲得バナー」が完結する共通部品。
// 状態（未配置シールの一覧・チップ座標）を自前で持ち、onAppear/onDisappear も
// 内部で完結させているため、呼び出し側の ResultView は
//     StickerRewardBanner()
// を1行差し込むだけでよい（@State や onAppear の追加は不要）。
//
// ロジックは EmojiQuizResultView.swift の同等ブロックを踏襲している。
// 詳しいシールの流れ（pendingStickers〜配置まで）は FinishedView.swift 冒頭を参照。

import SwiftUI

struct StickerRewardBanner: View {

    /// 今回のプレイで新たに獲得したシールの絵文字リスト。
    /// onAppear で StickerStore.pendingStickers から取得する。
    @State private var newStickerEmojis: [String] = []

    /// バナー内の各絵文字チップのグローバル座標（index → CGPoint）。
    /// ドラッグせずに画面を離れた場合、この位置へシールを自動配置するために使う。
    @State private var capturedPositions: [Int: CGPoint] = [:]

    private var screenSize: CGSize { UIScreen.main.bounds.size }

    var body: some View {
        VStack(spacing: 0) {
            // ★ この 0 サイズの土台を置いている理由 ★
            //   シール未獲得時にコンテナの中身が空になると、onAppear の付く先が無くなり
            //   一度も発火しない（＝ pendingStickers を取得できずバナーが永久に出ない）。
            //   常に実体のある子を1つ置くことで onAppear の発火を保証する。
            Color.clear.frame(width: 0, height: 0)

            if !newStickerEmojis.isEmpty {
                VStack(spacing: 8) {
                    Text("Got \(newStickerEmojis.count) Stickers!")
                        .font(.system(size: 15, weight: .black, design: .rounded))
                        .foregroundStyle(DS.primary)

                    HStack(spacing: 4) {
                        ForEach(Array(newStickerEmojis.enumerated()), id: \.offset) { idx, emoji in
                            DraggablePendingStickerChip(emoji: emoji) {
                                if let i = newStickerEmojis.firstIndex(of: emoji) {
                                    withAnimation(.easeIn(duration: 0.15)) {
                                        newStickerEmojis.remove(at: i)
                                        capturedPositions.removeValue(forKey: idx)
                                    }
                                }
                            }
                            .background(
                                GeometryReader { chipGeo in
                                    Color.clear.onAppear {
                                        let frame = chipGeo.frame(in: .global)
                                        capturedPositions[idx] = CGPoint(x: frame.midX, y: frame.midY)
                                    }
                                }
                            )
                        }
                    }

                    Text("Drag to Move")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(DS.muted)
                }
                .padding(.vertical, 14)
                .padding(.horizontal, 20)
                .frame(maxWidth: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: DS.sectionRadius)
                        .fill(DS.card)
                        .shadow(color: DS.primary.opacity(0.12), radius: 10, x: 0, y: 4)
                )
                .padding(.horizontal, 28)
                .padding(.bottom, 8)
                .transition(.scale(scale: 0.85).combined(with: .opacity))
            }
        }
        .onAppear {
            if !StickerStore.shared.pendingStickers.isEmpty {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.65)) {
                    newStickerEmojis = StickerStore.shared.pendingStickers
                }
            }
        }
        .onDisappear {
            placeRemainingStickers()
        }
    }

    // MARK: シール配置
    //
    // ⚠️ 変更注意: クランプ範囲 0.08〜0.92 は FinishedView.placeRemainingStickers /
    //   EmojiQuizResultView.placeRemainingStickers / DraggablePendingStickerChip.onEnded と
    //   揃えること。
    private func placeRemainingStickers() {
        guard !newStickerEmojis.isEmpty else { return }
        for (idx, emoji) in newStickerEmojis.enumerated() {
            if let pos = capturedPositions[idx] {
                StickerStore.shared.placePendingSticker(
                    emoji: emoji,
                    xRatio: max(0.08, min(0.92, pos.x / screenSize.width)),
                    yRatio: max(0.08, min(0.92, pos.y / screenSize.height))
                )
            } else {
                StickerStore.shared.confirmPendingStickers()
            }
        }
        newStickerEmojis = []
        capturedPositions = [:]
    }
}
