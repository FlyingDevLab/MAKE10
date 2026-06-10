//
//  DrawingToolbarView.swift
//  FDL-TenBlitz
//
//  Created by 空飛ぶ研究室(FlyingDevLab) on 2026/06/09.
//

// プレイキャンバス下部に固定表示するお絵かきツールバー。
//
// ★ 表示内容（お絵かきモード時）★
//   [モード切替] | [12色パレット] [消しゴム] [全消去]
//
// ★ 表示内容（ステッカーモード時）★
//   [モード切替]  ← これだけ（既存のステッカーUIを邪魔しない）
//
// ★ このビューの責務 ★
//   ユーザーの操作を DrawingStore に反映する。
//   全消去ボタンだけ誤操作防止のため確認アラートを出す。

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
            // モード切替ボタン
            // ─────────────────────────────
            modeToggleButton
                .padding(.horizontal, 12)

            // お絵かきモードのときだけパレット・ツールを表示
            if store.canvasMode == .drawing {

                // 縦の区切り線
                Divider()
                    .frame(height: 32)

                // ─────────────────────────────
                // 12色パレット ＋ 消しゴム ＋ 全消去
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

    // MARK: - Mode Toggle Button

    /// お絵かき ⇄ ステッカー の切り替えボタン
    private var modeToggleButton: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                store.canvasMode = store.canvasMode.toggled
                // モードを切り替えたら消しゴムをリセット（ステッカーモードから戻ったとき用）
                if store.canvasMode == .sticker {
                    store.isEraserMode = false
                }
            }
        } label: {
            VStack(spacing: 2) {
                Text(store.canvasMode == .drawing ? "🖍️" : "🌟")
                    .font(.system(size: 22))
                Text(store.canvasMode == .drawing
                     ? String(localized: "drawing_mode_label")
                     : String(localized: "sticker_mode_label"))
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(DS.textBody)
            }
            .frame(minWidth: 44, minHeight: 44)  // タッチターゲットを確保
        }
    }

    // MARK: - Color Button

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
        .accessibilityLabel(String(localized: String.LocalizationValue(drawingColor.nameKey)))
    }

    // MARK: - Eraser Button

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

    // MARK: - Clear Button

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
