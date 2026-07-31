//
//  StickerStorageView.swift
//  FDL-TenBlitz
//
//  Created by 空飛ぶ研究室(FlyingDevLab) on 2026/06/04.
//

// ストレージ画面。3行レイアウトで MAKE10・ストレージ・シール画面のシールを管理する。
//
// 【表示方針】
//   カルーセルは「1枚ずつ」ではなく「絵文字の種類ごと」にまとめて回す。
//   同じ絵文字は1スロットに集約し、中央に「×N」バッジで枚数を表示する。
//   これにより挿入順で散らばっていた重複がまとまり、目的の絵文字を探しやすくなる。
//   まとめは初出順（その種類が最初に現れた順）で安定させ、枚数が減っても並びが動かない。
//
// 【操作】
//   横フリック：各行の「絵文字の種類」を選択（循環）
//   縦フリック：選んだ種類の絵文字を1枚だけ隣の行へ移動
//     MAKE10行  下フリック → ストレージへ
//     ストレージ 上フリック → MAKE10へ  /  下フリック → シール画面へ
//     シール行  上フリック → ストレージへ

import SwiftUI

// MARK: - StickerStorageView

struct StickerStorageView: View {
    private let store = StickerStore.shared

    // 各行で現在選択中の「種類インデックス」（グループ配列に対するインデックス）
    @State private var gameIndex:    Int = 0
    @State private var storageIndex: Int = 0
    @State private var playIndex:    Int = 0

    // 横ドラッグのライブオフセット（カルーセルのスライド演出用）
    @State private var gameDragX:    CGFloat = 0
    @State private var storageDragX: CGFloat = 0
    @State private var playDragX:    CGFloat = 0

    // 移動アニメーション
    @State private var flyEmoji:     String  = ""
    @State private var flyY:         CGFloat = 0
    @State private var isFlying:     Bool    = false

    // 満杯・空メッセージ
    @State private var blockMessage: String? = nil

    // シール画面の表示フラグ
    @State private var showPlayView: Bool = false

    // スワイプ判定の閾値
    private let hThreshold: CGFloat = 40 // ← 変更可：横スワイプ感度
    private let vThreshold: CGFloat = 40 // ← 変更可：縦スワイプ感度

    // カルーセルの定数
    private let centerSize:  CGFloat = 96  // ← 変更可：選択中絵文字サイズ（中央）
    private let sideSize:    CGFloat = 42  // ← 変更可：隣接絵文字サイズ（±1）
    private let farSize:     CGFloat = 30  // ← 変更可：遠方絵文字サイズ（±2）
    private let sideOffset:  CGFloat = 52  // ← 変更可：隣接絵文字の中心からの距離
    private let farOffset:   CGFloat = 88  // ← 変更可：遠方絵文字の中心からの距離
    private let sideOpacity: Double  = 0.38 // ← 変更可：隣接絵文字の透明度
    private let farOpacity:  Double  = 0.20 // ← 変更可：遠方絵文字の透明度

    // ×N バッジの位置（中央絵文字の右下に重ねる）
    private let badgeOffsetX: CGFloat =  6  // ← 変更可：バッジの水平位置
    private let badgeOffsetY: CGFloat = -6  // ← 変更可：バッジの垂直位置

    // MARK: - グループ型
    // 絵文字1種類と、その枚数をまとめた表示用の値。
    private struct EmojiGroup: Identifiable {
        let emoji: String
        let count: Int
        var id: String { emoji }  // 種類ごとに一意なので絵文字そのものを ID にする
    }

    // MARK: - グループ計算（初出順・重複集約）

    // フラットな絵文字配列を「初出順の [種類, 枚数]」へ集約する。
    // 初出順を保つことで、枚数が増減してもスロット位置が動かず操作感が安定する。
    private func grouped(_ emojis: [String]) -> [EmojiGroup] {
        var order:  [String] = []          // 初めて出た順に絵文字を記録
        var counts: [String: Int] = [:]    // 絵文字 → 枚数
        for e in emojis {
            if counts[e] == nil { order.append(e) }
            counts[e, default: 0] += 1
        }
        // order の要素は直前のループで必ず counts に登録済みのため nil にならない
        return order.map { EmojiGroup(emoji: $0, count: counts[$0]!) }
    }

    // 各行の表示に使うグループ配列（store の変化に追従する計算プロパティ）
    private var gameGroups:    [EmojiGroup] { grouped(store.stickers.map { $0.emoji }) }
    private var storageGroups: [EmojiGroup] { grouped(store.storageEmojis) }
    private var playGroups:    [EmojiGroup] { grouped(store.playStickers.map { $0.emoji }) }

    // MARK: - body

    var body: some View {
        GeometryReader { geo in
            let rowH = geo.size.height / 3

            ZStack {
                VStack(spacing: 0) {
                    // 上行：MAKE10
                    rowView(
                        label:     String(localized: "make10_title"),
                        groups:    gameGroups,
                        index:     gameIndex,
                        countText: "\(displayGameCount) / 50",
                        dragX:     gameDragX,
                        hint:      String(localized: "sticker_storage_hint_down")
                    )
                    .frame(height: rowH)
                    .contentShape(Rectangle())
                    .gesture(makeGesture(row: .game, rowH: rowH))

                    Divider()

                    // 中行：ストレージ
                    rowView(
                        label:     String(localized: "sticker_storage_title"),
                        groups:    storageGroups,
                        index:     storageIndex,
                        countText: "\(store.storageEmojis.count)",
                        dragX:     storageDragX,
                        hint:      String(localized: "sticker_storage_hint_updown")
                    )
                    .frame(height: rowH)
                    .contentShape(Rectangle())
                    .gesture(makeGesture(row: .storage, rowH: rowH))

                    Divider()

                    // 下行：シール画面
                    rowView(
                        label:     String(localized: "game_picker_sticker"),
                        groups:    playGroups,
                        index:     playIndex,
                        countText: "\(store.playStickers.count) / 100",
                        dragX:     playDragX,
                        hint:      String(localized: "sticker_storage_hint_up")
                    )
                    .frame(height: rowH)
                    .contentShape(Rectangle())
                    .gesture(makeGesture(row: .play, rowH: rowH))
                }

                // 飛ぶ絵文字オーバーレイ
                if isFlying {
                    Text(flyEmoji)
                        .font(.system(size: 56))
                        .shadow(color: .black.opacity(0.15), radius: 6, x: 0, y: 3)
                        .position(x: geo.size.width / 2, y: flyY)
                        .allowsHitTesting(false)
                }

                // シール画面を開くボタン（下部固定）
                VStack {
                    Spacer()
                    Button {
                        showPlayView = true
                        SoundManager.shared.vibrate()
                    } label: {
                        Label(
                            LocalizedStringKey("sticker_open_play_mode"),
                            systemImage: "rectangle.expand.diagonal"
                        )
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 12)
                        .background(Capsule().fill(DS.primary))
                        .shadow(color: DS.primary.opacity(0.30), radius: 6, x: 0, y: 3)
                    }
                    .buttonStyle(.plain)
                    .padding(.bottom, 20)
                }

                // 満杯・空メッセージ
                if let msg = blockMessage {
                    Text(msg)
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .background(Capsule().fill(Color.black.opacity(0.72)))
                        .transition(.opacity.combined(with: .scale(scale: 0.9)))
                }
            }
        }
        .ignoresSafeArea(edges: .bottom)
        .fullScreenCover(isPresented: $showPlayView) {
            StickerPlayView()
        }
    }

    // MARK: - 行ビュー

    private func rowView(
        label:     String,
        groups:    [EmojiGroup],
        index:     Int,
        countText: String,
        dragX:     CGFloat,
        hint:      String
    ) -> some View {
        VStack(spacing: 4) {
            Spacer()

            HStack(alignment: .center, spacing: 0) {
                // ラベル
                Text(label)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .frame(width: 72, alignment: .leading)
                    .padding(.leading, 16)

                Spacer()

                // カルーセル
                emojiCarousel(groups: groups, index: index, dragX: dragX)

                Spacer()

                // 枚数（行全体の合計枚数）
                Text(countText)
                    .font(.system(size: 24, weight: .black, design: .rounded))
                    .foregroundStyle(DS.primary)
                    .frame(width: 72, alignment: .trailing)
                    .padding(.trailing, 16)
            }

            // ヒントテキスト
            Text(hint)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(Color(.tertiaryLabel))
                .padding(.bottom, 6)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - 絵文字カルーセル

    // 最大5スロット構成。ここでの N は「絵文字の種類数」（＝グループ数）。
    // 種類数に応じてスロットを中央から外側へ増やす。
    //   N=1: [🈳][🈳][①][🈳][🈳]
    //   N=2: [🈳][🈳][①][②][🈳]
    //   N=3: [🈳][③][①][②][🈳]
    //   N=4: [🈳][④][①][②][③]
    //   N≥5: [⑤][④][①][②][③]
    // 中央スロットのみ、枚数が2以上のとき「×N」バッジを重ねる（1枚のときは非表示）。
    // dragX に応じて各スロットが異なる速度でスライドし、奥行き感を演出する。
    private func emojiCarousel(groups: [EmojiGroup], index: Int, dragX: CGFloat) -> some View {
        let n = groups.count

        return ZStack {
            if n == 0 {
                Text("—")
                    .font(.system(size: 36))
                    .foregroundStyle(Color(.tertiaryLabel))
            } else {
                let i = min(index, n - 1)

                // ── 遠方左 L2：N≥5 のとき表示 ──
                if n >= 5 {
                    Text(groups[(i - 2 + n) % n].emoji)
                        .font(.system(size: farSize))
                        .opacity(farOpacity)
                        .offset(x: -farOffset + dragX * 0.65)
                        .animation(.interactiveSpring(), value: dragX)
                }

                // ── 隣接左 L1：N≥3 のとき表示 ──
                if n >= 3 {
                    Text(groups[(i - 1 + n) % n].emoji)
                        .font(.system(size: sideSize))
                        .opacity(sideOpacity)
                        .offset(x: -sideOffset + dragX * 0.45)
                        .animation(.interactiveSpring(), value: dragX)
                }

                // ── 中央：常に表示（枚数バッジ付き） ──
                centerSlot(group: groups[i])
                    .offset(x: dragX * 0.20)
                    .animation(.interactiveSpring(), value: dragX)

                // ── 隣接右 R1：N≥2 のとき表示 ──
                if n >= 2 {
                    Text(groups[(i + 1) % n].emoji)
                        .font(.system(size: sideSize))
                        .opacity(sideOpacity)
                        .offset(x: sideOffset + dragX * 0.45)
                        .animation(.interactiveSpring(), value: dragX)
                }

                // ── 遠方右 R2：N≥4 のとき表示 ──
                if n >= 4 {
                    Text(groups[(i + 2) % n].emoji)
                        .font(.system(size: farSize))
                        .opacity(farOpacity)
                        .offset(x: farOffset + dragX * 0.65)
                        .animation(.interactiveSpring(), value: dragX)
                }
            }
        }
        .frame(width: 210, height: centerSize + 8)
        .clipped()
    }

    // 中央スロット：大きい絵文字＋右下の枚数バッジ（2枚以上のときのみ）。
    private func centerSlot(group: EmojiGroup) -> some View {
        ZStack(alignment: .bottomTrailing) {
            Text(group.emoji)
                .font(.system(size: centerSize))

            if group.count >= 2 {
                countBadge(group.count)
                    .offset(x: badgeOffsetX, y: badgeOffsetY)
            }
        }
    }

    // 「×N」バッジ。ブランドカラーのカプセルで枚数を示す。
    private func countBadge(_ count: Int) -> some View {
        Text("×\(count)")
            .font(.system(size: 15, weight: .black, design: .rounded))
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Capsule().fill(DS.primary))
            .shadow(color: .black.opacity(0.15), radius: 2, x: 0, y: 1)
    }

    // MARK: - ジェスチャー生成

    private enum RowKind { case game, storage, play }

    private func makeGesture(row: RowKind, rowH: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 8)
            .onChanged { value in
                let isH = abs(value.translation.width) >= abs(value.translation.height)
                guard isH else { return }
                switch row {
                case .game:    gameDragX    = value.translation.width
                case .storage: storageDragX = value.translation.width
                case .play:    playDragX    = value.translation.width
                }
            }
            .onEnded { value in
                // ドラッグオフセットをリセット
                withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) {
                    gameDragX = 0; storageDragX = 0; playDragX = 0
                }

                let dx = value.translation.width
                let dy = value.translation.height

                if abs(dx) >= abs(dy) {
                    handleHorizontal(row: row, dx: dx)
                } else {
                    handleVertical(row: row, dy: dy, rowH: rowH)
                }
            }
    }

    // MARK: - 横スワイプ処理（種類選択）

    private func handleHorizontal(row: RowKind, dx: CGFloat) {
        guard abs(dx) >= hThreshold else { return }
        let forward = dx < 0  // 左スワイプ = 次へ進む
        SoundManager.shared.vibrate()

        switch row {
        case .game:
            let n = gameGroups.count
            guard n > 0 else { return }
            gameIndex = (gameIndex + (forward ? 1 : n - 1)) % n

        case .storage:
            let n = storageGroups.count
            guard n > 0 else { return }
            storageIndex = (storageIndex + (forward ? 1 : n - 1)) % n

        case .play:
            let n = playGroups.count
            guard n > 0 else { return }
            playIndex = (playIndex + (forward ? 1 : n - 1)) % n
        }
    }

    // MARK: - 縦スワイプ処理（移動：選択中の種類を1枚だけ動かす）

    private func handleVertical(row: RowKind, dy: CGFloat, rowH: CGFloat) {
        guard abs(dy) >= vThreshold else { return }
        let goDown = dy > 0

        switch row {
        case .game:
            // 下フリックのみ有効：MAKE10 → ストレージ
            guard goDown else { return }
            guard let emoji = selectedGameEmoji(),
                  // 同じ絵文字の先頭1枚を対象にする（位置・z順に影響しない閲覧用の集約なので先頭で良い）
                  let id = store.stickers.first(where: { $0.emoji == emoji })?.id
            else { showBlock(String(localized: "sticker_game_empty")); return }

            fly(emoji: emoji, fromY: rowH * 0.5, toY: rowH * 1.5) {
                store.moveGameToStorage(id: id)
                clampIndex(&gameIndex, count: gameGroups.count)
            }

        case .storage:
            guard let emoji = selectedStorageEmoji()
            else { showBlock(String(localized: "sticker_storage_empty")); return }

            if goDown {
                // ストレージ → シール画面
                guard store.playStickers.count < 100 else {
                    showBlock(String(localized: "sticker_play_full")); return
                }
                fly(emoji: emoji, fromY: rowH * 1.5, toY: rowH * 2.5) {
                    store.moveStorageToPlay(emoji: emoji)
                    clampIndex(&storageIndex, count: storageGroups.count)
                }
            } else {
                // ストレージ → MAKE10
                guard store.stickers.count < 50 else {
                    showBlock(String(localized: "sticker_game_full")); return
                }
                fly(emoji: emoji, fromY: rowH * 1.5, toY: rowH * 0.5) {
                    store.moveStorageToGame(emoji: emoji)
                    clampIndex(&storageIndex, count: storageGroups.count)
                }
            }

        case .play:
            // 上フリックのみ有効：シール画面 → ストレージ
            guard !goDown else { return }
            guard let emoji = selectedPlayEmoji(),
                  let id = store.playStickers.first(where: { $0.emoji == emoji })?.id
            else { showBlock(String(localized: "sticker_play_empty")); return }

            fly(emoji: emoji, fromY: rowH * 2.5, toY: rowH * 1.5) {
                store.movePlayToStorage(id: id)
                clampIndex(&playIndex, count: playGroups.count)
            }
        }
    }

    // MARK: - 飛行アニメーション

    private func fly(emoji: String, fromY: CGFloat, toY: CGFloat, completion: @escaping () -> Void) {
        SoundManager.shared.vibrate()
        flyEmoji   = emoji
        flyY       = fromY
        isFlying   = true

        withAnimation(.easeInOut(duration: 0.32)) {
            flyY = toY
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            completion()
            withAnimation(.easeOut(duration: 0.12)) { isFlying = false }
        }
    }

    // MARK: - ブロックメッセージ

    private func showBlock(_ msg: String) {
        SoundManager.shared.vibrate()
        withAnimation(.spring(response: 0.2)) { blockMessage = msg }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
            withAnimation { blockMessage = nil }
        }
    }

    // MARK: - 安全ヘルパー（選択中の種類 → 絵文字）

    private var displayGameCount: Int { min(store.stickers.count, 50) }

    // 各行で現在選択中のグループの絵文字を返す。空なら nil。
    private func selectedGameEmoji() -> String? {
        let g = gameGroups
        guard !g.isEmpty else { return nil }
        return g[min(gameIndex, g.count - 1)].emoji
    }

    private func selectedStorageEmoji() -> String? {
        let g = storageGroups
        guard !g.isEmpty else { return nil }
        return g[min(storageIndex, g.count - 1)].emoji
    }

    private func selectedPlayEmoji() -> String? {
        let g = playGroups
        guard !g.isEmpty else { return nil }
        return g[min(playIndex, g.count - 1)].emoji
    }

    private func clampIndex(_ index: inout Int, count: Int) {
        index = count == 0 ? 0 : min(index, count - 1)
    }
}
