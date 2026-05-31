//
//  CoinDropView.swift
//  FDL-TenBlitz
//
//  Created by 空飛ぶ研究室(FlyingDevLab) on 2026/05/30.
//
//  CoinDropViewModel.gameState に応じて
//    .title    → SwiftUI タイトル画面
//    .playing  → SpriteKit フィールド + SwiftUI HUD
//    .finished → SwiftUI リザルト画面
//  を切り替えるルートView。SharedFrame 内のコンテンツとして表示される。
//  PinballView と同じ構造・操作感に揃えている。

import SwiftUI
import SpriteKit

// MARK: - CoinDropView

struct CoinDropView: View {

    @State private var viewModel = CoinDropViewModel()
    @State private var scene: CoinDropScene?

    var body: some View {
        Group {
            switch viewModel.gameState {
            case .title:    CDTitleView(viewModel: viewModel)
            case .playing:  CDPlayingView(viewModel: viewModel, scene: $scene)
            case .finished: CDResultView(viewModel: viewModel, scene: $scene)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: viewModel.gameState)
        .onDisappear { scene?.isPaused = true }
    }
}

// MARK: - CDTitleView

private struct CDTitleView: View {
    var viewModel: CoinDropViewModel

    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            // 遊び方カード
            VStack(alignment: .leading, spacing: 12) {
                Label("How to Play", systemImage: "hand.draw.fill")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(DS.muted)

                howToRow("👆", "Drag coins to move them")
                howToRow("✨", "Same coins stick together and merge")
                howToRow("💵", "50¢ + 50¢ makes $1")
                howToRow("🎯", "Collect up to $10 = MAKE10!")
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(DS.card, in: RoundedRectangle(cornerRadius: DS.sectionRadius))
            .padding(.horizontal, 24)

            // コインの合体早見表
            VStack(spacing: 8) {
                mergeRow([.penny, .penny, .penny, .penny, .penny], into: .nickel)
                mergeRow([.nickel, .nickel], into: .dime)
                mergeRow([.dime, .dime, .dime, .dime, .dime], into: .halfDollar)
                mergeRow([.quarter, .quarter], into: .halfDollar)
                mergeRow([.halfDollar, .halfDollar], into: nil)
            }
            .padding(14)
            .frame(maxWidth: .infinity)
            .background(DS.card, in: RoundedRectangle(cornerRadius: DS.sectionRadius))
            .padding(.horizontal, 24)

            // ハイスコア
            if viewModel.highScore > 0 {
                HStack(spacing: 8) {
                    Text("🏆").font(.system(size: 20))
                    Text("Best Record")
                        .font(.system(size: 16, weight: .medium, design: .rounded))
                        .foregroundStyle(DS.muted)
                    Text("$\(viewModel.highScore)")
                        .font(.system(size: 24, weight: .black, design: .rounded))
                        .foregroundStyle(DS.accent)
                }
                .padding(.horizontal, 20).padding(.vertical, 10)
                .background(DS.card, in: RoundedRectangle(cornerRadius: DS.sectionRadius))
            }

            Spacer()

            Button {
                SoundManager.shared.vibrate()
                SoundManager.shared.playTap()
                viewModel.startGame()
            } label: {
                Text("ゲームスタート")
                    .font(.system(size: 26, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
                    .background(
                        RoundedRectangle(cornerRadius: DS.btnRadius)
                            .fill(DS.primary)
                            .shadow(color: DS.primary.opacity(0.35), radius: 8, x: 0, y: 4)
                    )
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
    }

    private func howToRow(_ icon: String, _ text: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(icon).font(.system(size: 18))
            Text(text)
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .foregroundStyle(DS.textPrimary)
        }
    }

    /// 「●●● → ◯」の合体早見行
    private func mergeRow(_ from: [CoinType], into: CoinType?) -> some View {
        HStack(spacing: 6) {
            ForEach(Array(from.enumerated()), id: \.offset) { _, c in
                CoinChip(type: c, size: 22)
            }
            Image(systemName: "arrow.right")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(DS.muted)
            if let into {
                CoinChip(type: into, size: 26)
            } else {
                Text("$1")
                    .font(.system(size: 16, weight: .black, design: .rounded))
                    .foregroundStyle(DS.gold)
            }
            Spacer()
        }
    }
}

// MARK: - CDPlayingView

private struct CDPlayingView: View {
    var viewModel: CoinDropViewModel
    @Binding var scene: CoinDropScene?

    var body: some View {
        ZStack(alignment: .top) {
            GeometryReader { _ in
                SpriteView(
                    scene: scene ?? CoinDropScene(size: CGSize(width: 390, height: 820)),
                    options: [.allowsTransparency]
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .ignoresSafeArea()
            }

            // ── HUD（スコア・残り時間・次のコイン）────────────
            VStack(spacing: 8) {
                HStack {
                    // スコア
                    VStack(alignment: .leading, spacing: 0) {
                        Text("SCORE")
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .foregroundStyle(DS.muted)
                        Text("$\(viewModel.score)")
                            .font(.system(size: 30, weight: .black, design: .rounded))
                            .foregroundStyle(DS.primary)
                    }

                    Spacer()

                    // 次のコイン
                    HStack(spacing: 6) {
                        Text("NEXT")
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundStyle(DS.muted)
                        CoinChip(type: viewModel.nextCoin, size: 30)
                    }

                    Spacer()

                    // 残り時間
                    VStack(alignment: .trailing, spacing: 0) {
                        Text("TIME")
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .foregroundStyle(DS.muted)
                        Text("\(viewModel.displaySeconds)")
                            .font(.system(size: 30, weight: .black, design: .rounded))
                            .foregroundStyle(viewModel.displaySeconds <= 10 ? DS.gaugeWarn : DS.textPrimary)
                            .monospacedDigit()
                    }
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: DS.sectionRadius)
                        .fill(DS.card.opacity(0.92))
                        .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 3)
                )
                .padding(.horizontal, 16)
                .padding(.top, 6)
            }
        }
        .onAppear {
            if let existing = scene {
                // 再スタート
                existing.isPaused = false
                existing.resetGame()
            } else {
                // 新規作成（コールバックを先に設定してから scene へ代入）
                let newScene = CoinDropScene(size: CGSize(width: 390, height: 820))
                newScene.scaleMode = .aspectFit
                newScene.onScoreChanged    = { viewModel.updateScore($0) }
                newScene.onSecondsChanged  = { viewModel.updateSeconds($0) }
                newScene.onNextCoinChanged = { viewModel.updateNextCoin($0) }
                newScene.onGameOver        = { viewModel.gameOver(reason: $0) }
                scene = newScene
                // didMove（地形構築）の後にラウンド開始
                DispatchQueue.main.async { newScene.resetGame() }
            }
        }
    }
}

// MARK: - CDResultView

private struct CDResultView: View {
    var viewModel: CoinDropViewModel
    @Binding var scene: CoinDropScene?

    private var reasonText: LocalizedStringKey {
        switch viewModel.gameOverReason {
        case .timeUp:   return "Time's Up!"
        case .overflow: return "Field Full!"
        }
    }

    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            // MAKE10 達成 / 新記録バナー
            if viewModel.isPerfect {
                Text("🎉 MAKE10! 🎉")
                    .font(.system(size: 24, weight: .black, design: .rounded))
                    .foregroundStyle(DS.gold)
                    .padding(.horizontal, 24).padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: DS.sectionRadius)
                            .fill(DS.gold.opacity(0.14))
                    )
                    .transition(.scale.combined(with: .opacity))
            } else if viewModel.isNewRecord {
                Text("🎉 New Record!")
                    .font(.system(size: 22, weight: .black, design: .rounded))
                    .foregroundStyle(DS.accent)
                    .padding(.horizontal, 24).padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: DS.sectionRadius)
                            .fill(DS.accent.opacity(0.12))
                    )
                    .transition(.scale.combined(with: .opacity))
            }

            // 終了理由
            Text(reasonText)
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundStyle(DS.muted)

            // スコア
            VStack(spacing: 4) {
                Text("Your Score")
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .foregroundStyle(DS.muted)
                Text("$\(viewModel.score)")
                    .font(.system(size: 60, weight: .black, design: .rounded))
                    .foregroundStyle(DS.primary)
                    .minimumScaleFactor(0.5)
            }
            .padding(.vertical, 20).frame(maxWidth: .infinity)
            .background(DS.card, in: RoundedRectangle(cornerRadius: DS.sectionRadius))
            .padding(.horizontal, 24)

            // ハイスコア
            HStack(spacing: 8) {
                Text("🏆").font(.system(size: 20))
                Text("Best Record")
                    .font(.system(size: 16, weight: .medium, design: .rounded))
                    .foregroundStyle(DS.muted)
                Text("$\(viewModel.highScore)")
                    .font(.system(size: 24, weight: .black, design: .rounded))
                    .foregroundStyle(DS.accent)
            }
            .padding(.horizontal, 20).padding(.vertical, 10)
            .background(DS.card, in: RoundedRectangle(cornerRadius: DS.sectionRadius))

            Spacer()

            VStack(spacing: 12) {
                Button {
                    SoundManager.shared.vibrate()
                    SoundManager.shared.playTap()
                    viewModel.startGame()
                } label: {
                    Text("Play Again")
                        .font(.system(size: 22, weight: .black, design: .rounded))
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

                Button {
                    SoundManager.shared.vibrate()
                    scene?.isPaused = true
                    scene = nil
                    withAnimation(.easeInOut(duration: 0.3)) {
                        viewModel.returnToTitle()
                    }
                } label: {
                    Text("Back to Title")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundStyle(DS.muted)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(DS.card, in: RoundedRectangle(cornerRadius: DS.btnRadius))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
    }
}

// MARK: - CoinChip（SwiftUI 上のコイン表示）

private struct CoinChip: View {
    let type: CoinType
    var size: CGFloat = 28

    var body: some View {
        ZStack {
            Circle()
                .fill(type.color)
                .overlay(Circle().stroke(.black.opacity(0.18), lineWidth: 1.5))
            Text(type.label)
                .font(.system(size: size * 0.42, weight: .black, design: .rounded))
                .foregroundStyle(Color(uiColor: type.labelUIColor))
                .minimumScaleFactor(0.5)
        }
        .frame(width: size, height: size)
    }
}
