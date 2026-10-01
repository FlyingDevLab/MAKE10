//
//  EmojiQuizResultView.swift
//  FDL-TenBlitz
//
//  Created by 空飛ぶ研究室(FlyingDevLab) on 2026/03/08.
//

// 絵文字クイズ終了後に表示する結果画面。
// スコア・メッセージ・円形ゲージで結果を視覚的に伝え、
// 今回増えたエネルギーも EnergyRewardBanner で見せる。
//
// 役割分担:
//   - EmojiQuizViewModel  : スコア・総問題数の算出元（この画面は表示するだけ）
//   - EmojiQuizResultView : 結果の視覚表現
//   - EnergyRewardBanner  : 今回増えたエネルギーの表示（共通部品）

import SwiftUI

// MARK: - EmojiQuizResultView

struct EmojiQuizResultView: View {

    // MARK: 依存

    var viewModel: EmojiQuizViewModel

    // MARK: 表示の算出

    /// 正解数を総問題数で割った正答率（0〜100の整数）。
    /// 各表示要素（絵文字・メッセージ・色）の分岐条件として使われる。
    private var percentage: Int {
        guard viewModel.totalCount > 0 else { return 0 }
        return Int(Double(viewModel.score) / Double(viewModel.totalCount) * 100)
    }

    /// 正答率に応じた結果絵文字を返す。100%なら🏆、以降スコアが下がるにつれ控えめな絵文字になる。
    /// ⚠️ 変更注意: 閾値（100 / 90 / 70 / 50 / 30）は下の resultMessage と揃えること。
    ///   片方だけ変えると「🎉なのにメッセージは普通」のような不一致が起きる。
    private var resultEmoji: String {
        switch percentage {
        case 100:       return "🏆"
        case 90..<100:  return "🎉"
        case 70..<90:   return "🌟"
        case 50..<70:   return "✨"
        case 30..<50:   return "😊"
        case 1..<30:    return "⭐"
        default:        return "🌈"
        }
    }

    /// 正答率に応じたローカライズ済みの結果メッセージを返す。
    /// ⚠️ 変更注意: 閾値は上の resultEmoji と揃えること（詳細はそちらを参照）。
    private var resultMessage: String {
        switch percentage {
        case 100:       return String(localized: "quiz_result_perfect")
        case 90..<100:  return String(localized: "quiz_result_excellent")
        case 70..<90:   return String(localized: "quiz_result_great")
        case 50..<70:   return String(localized: "quiz_result_good")
        case 30..<50:   return String(localized: "quiz_result_nice_try")
        case 1..<30:    return String(localized: "quiz_result_keep_going")
        default:        return String(localized: "quiz_result_try_again")
        }
    }

    /// 正答率に応じてスコア数字と円形ゲージの色を変える。
    /// 80%以上は緑（良好）、50%以上は金、それ以外はプライマリカラー。
    private var scoreColor: Color {
        switch percentage {
        case 80...: return DS.gaugeFull   // ← 変更可（色の閾値）
        case 50...: return DS.gold        // ← 変更可（色の閾値）
        default:    return DS.primary
        }
    }

    // MARK: body

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            // ── 結果カード ──────────────────────────────────
            // 絵文字＋メッセージ＋円形スコアゲージをまとめたメインコンテンツ
            VStack(spacing: 20) {
                VStack(spacing: 8) {
                    // 正答率に連動した結果絵文字。フォントサイズ72ptで画面の主役として表示する
                    Text(resultEmoji)
                        .font(.system(size: 72))
                    Text(resultMessage)
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                        .foregroundStyle(DS.primary)
                }
                Divider()

                // ── 円形スコアゲージ ──────────────────────────
                // ★ Circle.trim で円形ゲージを作る ★
                //   trim(from: 0, to: 0.7) は「円周の 0%〜70% の部分だけを描く」という
                //   意味で、これで弧（円グラフの一部分）が表現できます。
                //   ただし SwiftUI の円は「3時の方向」から描き始めるため、
                //   rotationEffect(-90度) で回転させて「12時の方向」スタートに補正します。
                //   円形プログレスバーを作るときの定番の組み合わせです。
                ZStack {
                    // ゲージの背景トラック（薄いグレーの全円）
                    Circle()
                        .stroke(DS.gaugeBg, lineWidth: 12)

                    // 正答率ぶんだけ弧を描く前景トラック
                    Circle()
                        .trim(from: 0, to: CGFloat(percentage) / 100)
                        .stroke(scoreColor, style: StrokeStyle(lineWidth: 12, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .animation(.easeOut(duration: 0.8), value: percentage)

                    // ゲージ中央に正解数と総問題数を重ねて表示する
                    VStack(spacing: 2) {
                        // 正解数をグラデーションカラーの大きな数字で強調する
                        Text("\(viewModel.score)")
                            .font(.system(size: 52, weight: .black, design: .rounded))
                            .foregroundStyle(LinearGradient(
                                colors: [scoreColor, DS.accent],
                                startPoint: .top, endPoint: .bottom
                            ))
                        // 「/ 10問」形式で総問題数を小さく添える。
                        // String(format: String(localized:), ...) = 「%lld もん」のような
                        // 引数付きのローカライズ文字列に値を埋め込む書き方
                        Text(String(format: String(localized: "quiz_result_total_count"), viewModel.totalCount))
                            .font(.system(size: 14, weight: .medium, design: .rounded))
                            .foregroundStyle(DS.muted)
                    }
                }
                .frame(width: 160, height: 160)
            }
            .padding(.vertical, 36)
            .padding(.horizontal, 32)
            .background(
                RoundedRectangle(cornerRadius: DS.cardRadius)
                    .fill(DS.card)
                    .shadow(color: .black.opacity(0.07), radius: 18, x: 0, y: 6)
            )
            .padding(.horizontal, 28)

            Spacer()

            // ── エネルギー獲得バナー ──────────────────────────
            EnergyRewardBanner()

            // ── 「もう一度」ボタン ────────────────────────────
            Button {
                viewModel.restart()
            } label: {
                Label("quiz_play_again", systemImage: "arrow.counterclockwise")
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
            .padding(.horizontal, 28)
            .padding(.bottom, 16)
        }
    }
}
