//
//  FinishedView.swift
//  FDL-TenBlitz
//
//  Created by 空飛ぶ研究室(FlyingDevLab) on 2026/03/08.
//

// MAKE10 のゲーム終了時に表示する結果画面。
// スコア表示・ハイスコア更新・Blitzモード解放バナー・エネルギー獲得バナーを状況に応じて表示する。
//
// ★ ハイスコアの表示条件について ★
//   以前は「Blitzで100問正解して解放されるまで隠す」仕組みだったが、
//   他のゲームと揃えて「記録が1つでもあれば表示する」方式に統一した。
//   30びょうと10びょうは別々のキーで記録され、currentHighScore が
//   今プレイしたモードの記録を返す。
//
// ★ エネルギーについて ★
//   プレイ中の正解ごとに GameViewModel が EnergyStore.earn() で加算している。
//   この画面では EnergyRewardBanner が「今回いくら増えたか」を演出付きで見せるだけ。

import SwiftUI

// MARK: - FinishedView

struct FinishedView: View {

    // MARK: 依存

    var viewModel: GameViewModel

    // MARK: ローカル状態

    /// 結果カードのポップインアニメーション用。onAppear で 1.0・1.0 に向けてアニメーションする。
    @State private var scale:   CGFloat = 0.75
    @State private var opacity: Double  = 0.0

    /// 誤タップ防止フラグ。アニメーション完了後（1秒後）に true になりボタンが有効化される。
    @State private var canTap:  Bool    = false

    // MARK: body

    /// この画面が使える場所の大きさ（回転・分割表示・Duo の開閉のたびに測り直す）。
    @State private var areaSize: CGSize = .zero

    /// 横長の並べ方にするか。
    private var isWide: Bool { DS.isWide(areaSize) }

    // ★ 横長の場所では、結果カードとボタンを左右に並べる理由 ★
    //   縦に積んだままだと、iPad を横にしたときなどに高さが足りず、下のボタンが画面の外へはみ出しやすい。
    //   左に結果カード、右に解放のお知らせ・エネルギー・ボタンを置けば、横に広い場所をそのまま使える。
    //   どちらにするかは端末の向きではなく「使える場所が横長かどうか」で決める（DS.isWide）。
    var body: some View {
        Group {
            if isWide {
                HStack(spacing: 24) {
                    resultCard
                        .frame(maxWidth: .infinity)
                    VStack(spacing: 0) {
                        unlockBanner
                        // ── エネルギー獲得バナー ──────────────────────────
                        EnergyRewardBanner()
                        playAgainButton
                            .padding(.bottom, 12)
                        backButton
                    }
                    .frame(maxWidth: .infinity)
                }
                .padding(.horizontal, 28)
                .frame(maxHeight: .infinity)
            } else {
                VStack(spacing: 0) {
                    Spacer()
                    resultCard
                        .padding(.horizontal, 28)
                    Spacer()
                    unlockBanner
                    // ── エネルギー獲得バナー ──────────────────────────
                    EnergyRewardBanner()
                    playAgainButton
                        .padding(.horizontal, 28)
                        .padding(.bottom, 12)
                    backButton
                }
            }
        }
        .onGeometryChange(for: CGSize.self) { proxy in
            proxy.size
        } action: { size in
            areaSize = size
        }
        .onAppear {
            // 結果カードをスケール＋フェードでポップインさせる
            withAnimation(.easeOut(duration: 0.45)) {
                scale   = 1.0
                opacity = 1.0
            }
            // アニメーション完了後1秒でボタンを有効化し、演出中の誤タップを防ぐ
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {   // ← 変更可（誤タップ防止の秒数）
                canTap = true
            }
        }
    }

    // MARK: 部品（縦長・横長の両方の並べ方で使う）

    private var resultCard: some View {
        // ── 結果カード ──────────────────────────────────
        // スコアが0のときは称賛テキストのみ、1以上のときはスコア数字も大きく表示する
        VStack(spacing: 12) {
            if viewModel.score == 0 {
                // 0問正解のときはスコア数字を出さず、励ましのメッセージだけを表示する
                Text(viewModel.praiseText)
                    .font(.system(size: 38, weight: .bold, design: .rounded))
                    .foregroundStyle(DS.primary)
                    .multilineTextAlignment(.center)
            } else {
                Text("finished_correct_label")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(DS.accent)

                // スコア数字。Blitzモードは赤系、通常モードは青系のグラデーションで区別する
                Text("\(viewModel.score)")
                    .font(.system(size: 120, weight: .black, design: .rounded))
                    .foregroundStyle(LinearGradient(
                        colors: [
                            viewModel.gameMode == .blitz ? DS.blitzColor : DS.primary,
                            DS.accent
                        ],
                        startPoint: .top, endPoint: .bottom
                    ))
                    .scaleEffect(1.05)
                    .shadow(color: DS.primary.opacity(0.25), radius: 8, x: 0, y: 4)

                Text(viewModel.praiseText)
                    .font(.system(size: 44, weight: .bold, design: .rounded))
                    .foregroundStyle(DS.primary)
                    .multilineTextAlignment(.center)

                // 記録が1つでもあればハイスコアセクションを表示する。
                // 30びょう・10びょうは別々に記録されるため、currentHighScore が
                // 今プレイしたモードの記録を返す（他のゲームの表示条件と揃えている）。
                if viewModel.currentHighScore > 0 {
                    Divider().padding(.horizontal, 20)
                    if viewModel.isNewHighScore {
                        // 今回が新記録のとき。ゴールドカラーで更新を強調する
                        Text("finished_high_score_updated")
                            .font(.system(size: 18, weight: .bold, design: .rounded))
                            .foregroundStyle(DS.gold)
                    } else {
                        // 更新なしのとき。現在のハイスコアをサブ表示として静かに添える
                        HStack(spacing: 6) {
                            Text("finished_high_score_label")
                                .font(.system(size: 15, weight: .medium, design: .rounded))
                                .foregroundStyle(DS.muted)
                            Text("\(viewModel.currentHighScore)")
                                .font(.system(size: 22, weight: .black, design: .rounded))
                                .foregroundStyle(DS.accent)
                        }
                    }
                }
            }
        }
        .padding(.vertical, isWide ? 20 : 40)     // ← 変更可（横長のときの上下の余白）
        .padding(.horizontal, 36)
        .background(DS.cardShadow())
        .clipShape(RoundedRectangle(cornerRadius: DS.cardRadius))
        // onAppear で 0.75→1.0 にアニメーションするポップインエフェクト
        .scaleEffect(scale)
        .opacity(opacity)
    }

    @ViewBuilder
    private var unlockBanner: some View {
        // ── Blitzモード解放バナー ────────────────────────
        // 初めて Blitz が解放されたセッションのみ表示する
        if viewModel.showUnlockBanner {
            VStack(spacing: 4) {
                Text("finished_unlock_title")
                    .font(.system(size: 24, weight: .black, design: .rounded))
                    .foregroundStyle(DS.blitzColor)
                Text("finished_unlock_message")
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundStyle(DS.textBody)
            }
            .padding(.vertical, 14)
            .padding(.horizontal, 28)
            .background(
                RoundedRectangle(cornerRadius: DS.sectionRadius)
                    .fill(DS.card)
                    .shadow(color: .black.opacity(0.08), radius: 10, x: 0, y: 4)
            )
            .padding(.bottom, 16)
            .transition(.scale.combined(with: .opacity))
        }
    }

    private var playAgainButton: some View {
        // ── 「もう一度」ボタン ────────────────────────────
        // canTap が true になるまでは無効化してアニメーション中の誤タップを防ぐ。
        // ボタン色はゲームモードに合わせて Blitz=赤系、通常=青系に切り替える
        Button {
            guard canTap else { return }
            withAnimation { viewModel.startGame(mode: viewModel.gameMode) }
        } label: {
            let color = viewModel.gameMode == .blitz ? DS.blitzColor : DS.primary
            Label("finished_play_again_button", systemImage: "arrow.counterclockwise")
                .font(.system(size: 18, weight: .black, design: .rounded))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 18)
                .background(
                    RoundedRectangle(cornerRadius: DS.btnRadius)
                        .fill(color)
                        .shadow(color: color.opacity(0.35), radius: 8, x: 0, y: 4)
                )
        }
        .buttonStyle(.plain)
        .disabled(!canTap)
    }

    @ViewBuilder
    private var backButton: some View {
        // ── 「もどる」ボタン ──────────────────────────────
        // Blitzモードが解放済みのときのみ表示する。
        // 未解放時は Spacer で同等の高さを確保してレイアウトが崩れないようにする
        if viewModel.isBlitzUnlocked {
            Button {
                guard canTap else { return }
                withAnimation { viewModel.returnToTitle() }
            } label: {
                Text("finished_back_button")
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                    .foregroundStyle(DS.muted)
                    .padding(.horizontal, 36)
                    .padding(.vertical, 11)
                    .background(Capsule().tintFill(Color.black.opacity(0.05)))
            }
            .buttonStyle(.plain)
            .disabled(!canTap)
            .padding(.bottom, 24)
        } else {
            // Blitz未解放時はボタンの代わりに Spacer で同じ高さを確保する
            Spacer().frame(height: 24)
        }
    }
}
