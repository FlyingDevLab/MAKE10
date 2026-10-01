//
//  JankenResultView.swift
//  FDL-TenBlitz
//
//  Created by 空飛ぶ研究室(FlyingDevLab) on 2026/06/03.
//
//  ① 一言サマリ
//  指令じゃんけん（Command Janken）のリザルト画面。
//  クリアタイム・ベストタイム更新・正解率・エネルギー獲得バナーを表示する。
//
//  ② 役割分担
//    - View（このファイル）       : 結果の表示
//    - ViewModel (JankenViewModel): タイム・正解率・新記録などの結果データを提供
//    - EnergyRewardBanner         : 今回増えたエネルギー（クリアボーナス）の表示（共通部品）
//
//  ★ ポップインアニメは FinishedView.swift と同じ仕組み ★

import SwiftUI

// MARK: - JankenResultView

/// じゃんけんのリザルト画面。結果カード → エネルギー獲得バナー → ボタン群を縦に並べる。
struct JankenResultView: View {

    var viewModel: JankenViewModel

    // 結果カードのポップインアニメーション用
    @State private var scale:   CGFloat = 0.75
    @State private var opacity: Double  = 0.0

    // アニメーション完了後にtrueになりボタンを有効化する（誤タップ防止）
    @State private var canTap: Bool = false

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

            // ── エネルギー獲得バナー ──────────────────────────
            EnergyRewardBanner()

            // ── ボタン群 ──────────────────────────────────────
            VStack(spacing: 12) {

                // もう一度（同じ難易度でリスタート）
                Button {
                    guard canTap else { return }
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
        }
    }
}
