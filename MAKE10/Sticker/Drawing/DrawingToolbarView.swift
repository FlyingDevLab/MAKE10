//
//  DrawingToolbarView.swift
//  FDL-TenBlitz
//
//  Created by 空飛ぶ研究室(FlyingDevLab) on 2026/06/09.
//

// プレイキャンバス下部に固定表示するお絵かきツールバー。
//
// ★ 表示内容（常時）★
//   [シールロック切替] | [12色パレット] [消しゴム] [全消去]
//
// ★ このビューの責務 ★
//   ユーザーの操作を DrawingStore に反映する。
//   全消去ボタンだけ誤操作防止のため確認アラートを出す。
//
// ★ 以前は「お絵かき⇄シール移動」の排他モード切替ボタンだったが、
//   お絵かきを常時有効にしたことに伴い役割を変更した。
//   このボタンは今は「シールを固定するかどうか」だけを切り替える。
//   パレットも表示/非表示を切り替える必要がなくなったため常時表示にした。

import SwiftUI

// MARK: - DrawingToolbarView

struct DrawingToolbarView: View {

    @State private var store           = DrawingStore.shared
    @State private var showClearAlert  = false  // 全消去の確認アラート表示フラグ

    // ツールバー内のカラーボタンのサイズ定数。← 変更可
    private let colorCircleSize: CGFloat = 30  // 色ボタンの直径 ← 変更可
    private let toolButtonSize:  CGFloat = 36  // 消しゴム・全消去ボタンのサイズ ← 変更可

    var body: some View {
        HStack(spacing: 0) {

            // ─────────────────────────────
            // シールロック切替ボタン
            // ─────────────────────────────
            stickerLockButton
                .padding(.horizontal, 12)

            // 縦の区切り線
            Divider()
                .frame(height: 32)

            // ─────────────────────────────
            // 12色パレット ＋ 消しゴム ＋ 全消去（常時表示）
            // 色が多いので ScrollView で横スクロールにする
            // ─────────────────────────────
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {

                    // カラーパレット
                    ForEach(DrawingColor.palette, id: \.hex) { drawingColor in
                        colorButton(drawingColor)
                    }

                    // 区切り
                    Divider()
                        .frame(height: 28)
                        .padding(.horizontal, 2)

                    // 消しゴムボタン
                    eraserButton

                    // 全消去ボタン
                    clearButton
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
            }
        }
        .frame(maxWidth: .infinity)
        .background(
            // すりガラス風の背景（ステッカーの上に重なっても見やすいように）
            .ultraThinMaterial,
            in: RoundedRectangle(cornerRadius: DS.chipRadius)
        )
        // ─────────────────────────────
        // 全消去確認アラート
        // ─────────────────────────────
        .alert(
            String(localized: "drawing_clear_alert_title"),
            isPresented: $showClearAlert
        ) {
            Button(String(localized: "drawing_clear_confirm"),
                   role: .destructive) {
                store.clearAll()
            }
            Button(String(localized: "drawing_clear_cancel"),
                   role: .cancel) {}
        } message: {
            Text("drawing_clear_alert_message")
        }
    }

    // MARK: - シールロック切替ボタン

    /// シールを固定（ロック）するかどうかを切り替えるボタン。
    /// ロック中はシールが動かせず、お絵かきに集中できる。
    /// ロック解除中はシールをドラッグして自由に動かせる。
    private var stickerLockButton: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                store.isStickerLocked.toggle()
            }
        } label: {
            VStack(spacing: 2) {
                Text(store.isStickerLocked ? "🔒" : "🔓")
                    .font(.system(size: 22))
                Text(store.isStickerLocked
                     ? String(localized: "sticker_locked_label")
                     : String(localized: "sticker_unlocked_label"))
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(DS.textBody)
            }
            .frame(minWidth: 44, minHeight: 44)  // タッチターゲットを確保
        }
        .accessibilityLabel(store.isStickerLocked
             ? String(localized: "sticker_locked_label")
             : String(localized: "sticker_unlocked_label"))
    }

    // MARK: - カラーボタン

    /// パレットの1色ボタン
    @ViewBuilder
    private func colorButton(_ drawingColor: DrawingColor) -> some View {
        let isSelected = !store.isEraserMode && store.currentColorHex == drawingColor.hex

        Button {
            store.currentColorHex = drawingColor.hex
            store.isEraserMode    = false
        } label: {
            ZStack {
                // 色の円
                Circle()
                    .fill(Color(hex: drawingColor.hex))
                    .frame(width: colorCircleSize, height: colorCircleSize)
                    // 白は背景と区別するため枠線を追加
                    .overlay(
                        Circle()
                            .stroke(
                                drawingColor.hex == "#FFFFFF"
                                    ? Color.gray.opacity(0.4)
                                    : Color.clear,
                                lineWidth: 1
                            )
                    )

                // 選択中インジケーター：外側に強調リング
                if isSelected {
                    Circle()
                        .stroke(Color(hex: drawingColor.hex), lineWidth: 2)
                        .frame(width: colorCircleSize + 6,
                               height: colorCircleSize + 6)
                        // 暗い色の場合はリングが見えにくいので白で補助
                        .overlay(
                            Circle()
                                .stroke(Color.white.opacity(0.5), lineWidth: 1)
                                .frame(width: colorCircleSize + 9,
                                       height: colorCircleSize + 9)
                        )
                }
            }
            .frame(width: colorCircleSize + 10, height: colorCircleSize + 10)  // タッチ領域
        }
        .buttonStyle(.plain)
        .scaleEffect(isSelected ? 1.15 : 1.0)
        .animation(.spring(response: 0.25), value: isSelected)
        // ★ LocalizedStringKey を直接渡すことで翻訳が引かれる。
        //   以前は String.LocalizationValue に変換していたため自動抽出が効かず、
        //   VoiceOver が「drawing_color_red」とキー名を読み上げていた。
        .accessibilityLabel(drawingColor.name.key)
    }

    // MARK: - 消しゴムボタン

    /// 消しゴムボタン
    private var eraserButton: some View {
        Button {
            store.isEraserMode.toggle()
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: DS.smallRadius)
                    .fill(store.isEraserMode
                          ? DS.primary.opacity(0.15)
                          : Color.clear)
                    .frame(width: toolButtonSize, height: toolButtonSize)

                Text("🪄")
                    .font(.system(size: 20))
            }
            .frame(width: toolButtonSize + 8, height: toolButtonSize + 8)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(String(localized: "drawing_eraser_label"))
    }

    // MARK: - 全消去ボタン

    /// 全消去ボタン（タップでアラートを表示）
    private var clearButton: some View {
        Button {
            showClearAlert = true
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: DS.smallRadius)
                    .fill(Color.clear)
                    .frame(width: toolButtonSize, height: toolButtonSize)

                Text("🗑️")
                    .font(.system(size: 20))
            }
            .frame(width: toolButtonSize + 8, height: toolButtonSize + 8)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(String(localized: "drawing_clear_label"))
    }
}
