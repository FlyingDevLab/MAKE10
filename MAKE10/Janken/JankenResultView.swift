//
//  JankenResultView.swift
//  FDL-TenBlitz
//
//  Created by 空飛ぶ研究室(FlyingDevLab) on 2026/06/03.
//
//  ① 一言サマリ
//  指令じゃんけん（Command Janken）のリザルト画面。
//  クリアタイム・ベストタイム更新・正解率・シール獲得バナーを表示し、
//  獲得シールをその場でドラッグ配置できる。
//
//  ② 役割分担
//    - View（このファイル）  : 結果の表示と、獲得シールの配置操作
//    - ViewModel (JankenViewModel): タイム・正解率・新記録などの結果データを提供
//    - StickerStore          : 獲得シール（pending）の保持・配置確定
//
//  ★ ポップインアニメ・シールのドラッグ配置・「見えない背景での座標取得＋比率保存」は
//     FinishedView.swift と同じ仕組み。詳しい解説は FinishedView.swift を参照 ★

import SwiftUI

// MARK: - JankenResultView

/// じゃんけんのリザルト画面。結果カード → シール獲得バナー → ボタン群を縦に並べる。
struct JankenResultView: View {

    var viewModel: JankenViewModel

    // 結果カードのポップインアニメーション用
    @State private var scale:   CGFloat = 0.75
    @State private var opacity: Double  = 0.0

    // アニメーション完了後にtrueになりボタンを有効化する（誤タップ防止）
    @State private var canTap: Bool = false

    // 獲得シールのリスト。バナーに表示しドラッグで配置できる。
    @State private var newStickerEmojis: [String] = []

    // バナー内の各絵文字チップのグローバル座標（自動配置のために記録）
    // ★ 見えない背景Viewで frame(in: .global) を読む手法は FinishedView.swift 参照 ★
    @State private var capturedPositions: [Int: CGPoint] = [:]

    /// 画面サイズ。シール位置を「画面に対する比率」へ変換するときの分母に使う。
    private var screenSize: CGSize { UIScreen.main.bounds.size }

    // 正解率の表示文字列（例：8/10 (80%)）
    private var accuracyText: String {
        let total   = viewModel.totalRounds
        let correct = total - viewModel.missCount
        let pct     = Int(viewModel.finalAccuracy * 100)
        return "\(correct) / \(total)  (\(pct)%)"
    }

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            // ── 結果カード ────────────────────────────────────
            VStack(spacing: 16) {

                // 難易度ラベル
                Text(viewModel.difficulty.labelKey)
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(DS.muted)

                // ── タイム（メイン）──────────────────────────
                VStack(spacing: 4) {
                    Text("janken_result_time_label")
                        .font(.system(size: 16, weight: .medium, design: .rounded))
                        .foregroundStyle(DS.accent)

                    Text(viewModel.elapsedFormatted)
                        .font(.system(size: 64, weight: .black, design: .rounded))  // ← 変更可
                        .foregroundStyle(
                            LinearGradient(
                                colors: [DS.primary, DS.accent],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .monospacedDigit()   // 数字幅を固定して横揺れを防ぐ
                        .shadow(color: DS.primary.opacity(0.2), radius: 6, x: 0, y: 3)
                }

                Divider().padding(.horizontal, 16)

                // ── ベストタイム ──────────────────────────────
                if viewModel.isNewBest {
                    // 新記録のとき
                    Text("janken_result_new_best")
                        .font(.system(size: 20, weight: .black, design: .rounded))
                        .foregroundStyle(DS.gold)
                } else if let best = viewModel.bestTimeFormatted {
                    // 記録あり・未更新のとき
                    HStack(spacing: 6) {
                        Text("janken_result_best_label")
                            .font(.system(size: 15, weight: .medium, design: .rounded))
                            .foregroundStyle(DS.muted)
                        Text(best)
                            .font(.system(size: 20, weight: .black, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(DS.accent)
                    }
                }

                // ── 正解率 ────────────────────────────────────
                HStack(spacing: 6) {
                    Text("janken_result_accuracy_label")
                        .font(.system(size: 15, weight: .medium, design: .rounded))
                        .foregroundStyle(DS.muted)
                    Text(accuracyText)
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        .foregroundStyle(DS.textPrimary)
                }
            }
            .padding(.vertical, 36)
            .padding(.horizontal, 32)
            .background(DS.cardShadow())
            .clipShape(RoundedRectangle(cornerRadius: DS.cardRadius))
            .padding(.horizontal, 28)
            // ポップイン：onAppear で scale/opacity を変化させて拡大フェードインする
            .scaleEffect(scale)
            .opacity(opacity)

            Spacer()

            // ── シール獲得バナー ──────────────────────────────
            if !newStickerEmojis.isEmpty {
                VStack(spacing: 8) {
                    Text("Got \(newStickerEmojis.count) Stickers!")
                        .font(.system(size: 15, weight: .black, design: .rounded))
                        .foregroundStyle(DS.primary)

                    HStack(spacing: 4) {
                        ForEach(Array(newStickerEmojis.enumerated()), id: \.offset) { idx, emoji in
                            DraggablePendingStickerChip(emoji: emoji) {
                                // ドラッグで配置確定されたチップはバナーから取り除く
                                if let i = newStickerEmojis.firstIndex(of: emoji) {
                                    withAnimation(.easeIn(duration: 0.15)) {
                                        newStickerEmojis.remove(at: i)
                                        capturedPositions.removeValue(forKey: idx)
                                    }
                                }
                            }
                            // 透明な背景Viewでチップの中心グローバル座標を記録しておく
                            // （未ドラッグのシールを後でこの位置に自動配置するため）
                            .background(
                                GeometryReader { chipGeo in
                                    Color.clear.onAppear {
                                        let frame = chipGeo.frame(in: .global)
                                        capturedPositions[idx] = CGPoint(
                                            x: frame.midX, y: frame.midY
                                        )
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
                .padding(.bottom, 16)
                .transition(.scale(scale: 0.85).combined(with: .opacity))
            }

            // ── ボタン群 ──────────────────────────────────────
            VStack(spacing: 12) {

                // もう一度（同じ難易度でリスタート）
                Button {
                    guard canTap else { return }
                    placeRemainingStickers()
                    withAnimation { viewModel.restart() }
                } label: {
                    Label("janken_result_play_again", systemImage: "arrow.counterclockwise")
                        .font(.system(size: 18, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 18)
                        .background(
                            RoundedRectangle(cornerRadius: DS.btnRadius)
                                .fill(DS.primary)
                                .shadow(color: DS.primary.opacity(0.35), radius: 8, x: 0, y: 4)
                        )
                }
                .buttonStyle(.plain)
                .disabled(!canTap)

                // 難易度選択に戻る
                Button {
                    guard canTap else { return }
                    placeRemainingStickers()
                    withAnimation(.easeInOut(duration: 0.3)) { viewModel.goToIdle() }
                } label: {
                    Text("janken_result_back_button")
                        .font(.system(size: 18, weight: .semibold, design: .rounded))
                        .foregroundStyle(DS.muted)
                        .padding(.horizontal, 36)
                        .padding(.vertical, 11)
                        .background(Capsule().fill(Color.black.opacity(0.05)))
                }
                .buttonStyle(.plain)
                .disabled(!canTap)
            }
            .padding(.horizontal, 28)
            .padding(.bottom, 28)
        }
        .onAppear {
            // 結果カードのポップイン
            withAnimation(.easeOut(duration: 0.45)) {
                scale   = 1.0
                opacity = 1.0
            }
            // 1秒後にボタンを有効化（演出中の誤タップ防止）
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                canTap = true
            }
            // 獲得シールをバナーに表示
            if !StickerStore.shared.pendingStickers.isEmpty {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.65)) {
                    newStickerEmojis = StickerStore.shared.pendingStickers
                }
            }
        }
        .onDisappear {
            // 画面を離れる際、未配置のシールも取りこぼさず確定する
            placeRemainingStickers()
        }
    }

    // MARK: - シール配置

    /// ドラッグされなかった残りのシールをバナー上の位置に自動配置する。
    /// 座標は screenSize で割って「画面に対する比率(0.08〜0.92)」に変換して保存する
    /// （端末サイズが変わっても同じ相対位置に再現できるようにするため。手法は FinishedView 参照）。
    private func placeRemainingStickers() {
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
        newStickerEmojis    = []
        capturedPositions   = [:]
    }
}
