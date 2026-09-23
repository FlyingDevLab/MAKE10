//
//  DrawingToolbarView.swift
//  FDL-TenBlitz
//
//  Created by 空飛ぶ研究室(FlyingDevLab) on 2026/06/09.
//

// プレイキャンバス下部に固定表示するお絵かきツールバー。
//
// ★ 表示内容（常時）★
//   [元に戻す] | [12色パレット] [消しゴム] [全消去]
//
// ★ このビューの責務 ★
//   ユーザーの操作を DrawingStore に反映する。
//   全消去ボタンだけ誤操作防止のため確認アラートを出す。
//
// ★ 左端のボタンの変遷 ★
//   排他モード切替 → シールロック → 元に戻す（現在）。
//   シールは「長押しで掴む」方式になり、なぞるだけでは動かなくなったため
//   ロックの必要がなくなり、代わりに描画の取り消しを置いた。

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
            // 元に戻すボタン
            // ─────────────────────────────
            undoButton
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

    // MARK: - 元に戻すボタン

    /// 最後に描いた線を1本消すボタン。線が無いときは薄く表示して無効にする。
    private var undoButton: some View {
        Button {
            store.undo()
            SoundManager.shared.vibrate()
        } label: {
            VStack(spacing: 2) {
                Image(systemName: "arrow.uturn.backward")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(DS.textBody)
                Text("drawing_undo_label")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(DS.textBody)
            }
            .frame(minWidth: 44, minHeight: 44)  // タッチターゲットを確保
            .opacity(store.canUndo ? 1.0 : 0.35)
        }
        .buttonStyle(.plain)
        .disabled(!store.canUndo)
        .accessibilityLabel(String(localized: "drawing_undo_label"))
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
