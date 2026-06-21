//
//  PinballView.swift
//  FDL-TenBlitz
//
//  Created by 空飛ぶ研究室(FlyingDevLab) on 2026/04/13.
//
//  ① 一言サマリ
//  ピンボールのルートView。PinballViewModel の gameState に応じて
//    .title    → SwiftUI タイトル画面
//    .playing  → SpriteKit ゲーム画面 (SpriteView)
//    .finished → SwiftUI リザルト画面
//  を切り替える。SharedFrame 内のコンテンツとして表示される。
//
//  ② 役割分担
//    - View（このファイル）  : 画面切り替えと、SpriteKit シーンの生成・保持・リセット
//    - ViewModel (PinballViewModel): スコア・残機・状態の保持
//    - Scene (PinballScene)  : 物理シミュレーション本体
//
//  ★ SpriteView とは？ ★
//    SwiftUI の中に SpriteKit のシーン(SKScene)を埋め込むための橋渡しView。
//    このファイルでは scene を @State で保持し、初回に1つ作って使い回す。
//    再スタート時は作り直さず resetGame() で中身だけ戻し、画面を離れるときは
//    isPaused で物理を止める（毎回作り直すと重く、状態も失われるため）。
//
//  ★ SpriteKit そのもの（ノード・物理）の入門解説は CoinDropScene.swift を参照 ★
//  ★ @Binding の解説は SettingsView.swift / GeometryReader は ConfettiView.swift 参照 ★

import SwiftUI
import SpriteKit

// MARK: - PinballView

/// gameState を見て3画面を出し分けるルート。SpriteKit シーンの生存管理もここが持つ。
struct PinballView: View {

    @State private var viewModel = PinballViewModel()
    // SpriteKit シーンは playing 中のみ保持し、再スタート時に reset する
    @State private var scene: PinballScene?

    var body: some View {
        Group {
            switch viewModel.gameState {
            case .title:    PBTitleView(viewModel: viewModel)
            case .playing:  PBPlayingView(viewModel: viewModel, scene: $scene)
            case .finished: PBResultView(viewModel: viewModel, scene: $scene)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: viewModel.gameState)
        .onDisappear { scene?.isPaused = true }   // 画面を離れたら物理を一時停止
    }
}

// MARK: - PBTitleView（タイトル画面）

/// タイトル画面。遊び方カード・ハイスコア・スタートボタンを縦に並べる。
private struct PBTitleView: View {
    var viewModel: PinballViewModel

    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            // 遊び方カード
            VStack(alignment: .leading, spacing: 12) {
                Label("How to Play", systemImage: "gamecontroller.fill")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(DS.muted)

                HStack(alignment: .top, spacing: 8) {
                    Text("👈").font(.system(size: 18))
                    Text("Tap Left → Left Flipper")
                        .font(.system(size: 15, weight: .medium, design: .rounded))
                        .foregroundStyle(DS.textPrimary)
                }
                HStack(alignment: .top, spacing: 8) {
                    Text("👉").font(.system(size: 18))
                    Text("Tap Right → Right Flipper")
                        .font(.system(size: 15, weight: .medium, design: .rounded))
                        .foregroundStyle(DS.textPrimary)
                }
                HStack(alignment: .top, spacing: 8) {
                    Text("🎱").font(.system(size: 18))
                    Text("Lose a life each time the ball drops. 3 lives total!")
                        .font(.system(size: 15, weight: .medium, design: .rounded))
                        .foregroundStyle(DS.textPrimary)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(DS.card, in: RoundedRectangle(cornerRadius: DS.sectionRadius))
            .padding(.horizontal, 24)

            // ハイスコア
            if viewModel.highScore > 0 {
                HStack(spacing: 8) {
                    Text("🏆").font(.system(size: 20))
                    Text("Best Record")
                        .font(.system(size: 16, weight: .medium, design: .rounded))
                        .foregroundStyle(DS.muted)
                    Text("\(viewModel.highScore)")
                        .font(.system(size: 24, weight: .black, design: .rounded))
                        .foregroundStyle(DS.accent)
                }
                .padding(.horizontal, 20).padding(.vertical, 10)
                .background(DS.card, in: RoundedRectangle(cornerRadius: DS.sectionRadius))
            }

            Spacer()

            // スタートボタン
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
}

// MARK: - PBPlayingView（ゲーム画面）

/// SpriteKit シーンを表示するプレイ画面。シーンの生成・再利用・コールバック接続を担う。
private struct PBPlayingView: View {
    var viewModel: PinballViewModel
    @Binding var scene: PinballScene?

    var body: some View {
        GeometryReader { geo in
            let sceneSize = CGSize(width: 390, height: 700)
            let skView = makeSpriteView(sceneSize: sceneSize, viewSize: geo.size)
            skView
                .ignoresSafeArea()
        }
        .onAppear {
            if let existing = scene {
                // 再スタート時はリセット（シーンは作り直さず中身だけ初期化）
                existing.isPaused = false
                existing.resetGame(ballsLeft: viewModel.ballsLeft)
            } else {
                // 新規作成
                let newScene = PinballScene(size: CGSize(width: 390, height: 700))
                newScene.scaleMode = .aspectFit
                // Scene → ViewModel への通知をつなぐ（スコア更新・ボール落下）
                newScene.onScoreChanged = { viewModel.updateScore($0) }
                newScene.onBallDrained  = {
                    viewModel.ballDrained()
                    if viewModel.ballsLeft > 0 {
                        // 残機あり → 次のボールを発射
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                            newScene.launchBall()
                            newScene.updateBallsHUD(ballsLeft: viewModel.ballsLeft)
                        }
                    }
                    // 残機0の場合は PinballViewModel.ballDrained() が endGame を呼ぶ
                }
                scene = newScene
            }
        }
    }

    /// SpriteView を組み立てて返す。scene が未生成の場合の保険として一時シーンを渡す。
    @MainActor
    private func makeSpriteView(sceneSize: CGSize, viewSize: CGSize) -> some View {
        SpriteView(
            scene: scene ?? PinballScene(size: sceneSize),
            options: [.allowsTransparency]
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - PBResultView（リザルト画面）

/// ゲームオーバー画面。新記録バナー・スコア・ハイスコアと、もう一度／タイトルへ戻るボタン。
private struct PBResultView: View {
    var viewModel: PinballViewModel
    @Binding var scene: PinballScene?

    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            // 新記録バナー
            if viewModel.isNewRecord {
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

            // スコア
            VStack(spacing: 4) {
                Text("Your Score")
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .foregroundStyle(DS.muted)
                Text("\(viewModel.score)")
                    .font(.system(size: 60, weight: .black, design: .rounded))
                    .foregroundStyle(DS.primary)
                    .minimumScaleFactor(0.5)   // 桁が多いときは自動で縮小して枠内に収める
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
                Text("\(viewModel.highScore)")
                    .font(.system(size: 24, weight: .black, design: .rounded))
                    .foregroundStyle(DS.accent)
            }
            .padding(.horizontal, 20).padding(.vertical, 10)
            .background(DS.card, in: RoundedRectangle(cornerRadius: DS.sectionRadius))

            Spacer()

            VStack(spacing: 12) {
                // もう一度
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

                // タイトルへ
                Button {
                    SoundManager.shared.vibrate()
                    scene?.isPaused = true   // 物理を止めてからシーンを破棄
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
