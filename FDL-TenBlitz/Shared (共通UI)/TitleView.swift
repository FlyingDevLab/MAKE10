//
//  TitleView.swift
//  FDL-TenBlitz
//
//  Created by 空飛ぶ研究室(FlyingDevLab) on 2026/03/08.
//

// タイトル画面のルートビュー。
// アニメーションカード・ハイスコア・ゲーム選択グリッドを管理する。
//
// ★ 旧バージョンからの変更点 ★
//   「30びょう」「10びょう」の ModeButton と「その他ゲーム」ボタンを廃止し、
//   全ゲームを統一サイズの GamePickerTile で2列グリッドに並べた。
//   フリック操作で並び替えができ、並び順は GameRankManager が UserDefaults に永続化する。
//   blitz（10びょう）は isBlitzUnlocked が true になるまで非表示にする。
//
// ★ このファイルの構成 ★
//   TitleView（親）
//     ├ アニメーションカード … 「n + (10-n) = 10」をループアニメで表示
//     │                        5ループごとに FDL ロゴスプラッシュを挟む
//     ├ ハイスコア表示       … isHighScoreUnlocked が true のときのみ表示
//     └ ゲーム選択グリッド   … GamePickerTile を LazyVGrid で2列に並べる

import SwiftUI

struct TitleView: View {
    var viewModel:    GameViewModel
    /// タイルがタップされたときに呼ばれるコールバック。
    /// MakeTenContentView が画面遷移・ゲーム開始を担う。
    var onSelectGame: (GamePickerSelection) -> Void

    private let offScreenLeading: CGFloat = -220

    // MARK: - Animation State

    @State private var centerNumber:    Int     = Int.random(in: 1...9)
    @State private var incomingNumber:  Int     = 0
    @State private var incomingOffsetX: CGFloat = -220
    @State private var showPlus:        Bool    = false
    @State private var showTen:         Bool    = false
    @State private var tenScale:        CGFloat = 1.0
    @State private var sparkOpacity:    Double  = 0.0
    @State private var sparkOffsetY:    CGFloat = 0
    @State private var loopGeneration:  Int     = 0

    // MARK: - Game Grid State

    /// ゲームタイルの並び順を管理する（UserDefaults に永続化）
    @State private var rankManager = GameRankManager()
    /// 末尾送り演出中のタイルのフライオフセット（キー: ゲーム、値: 飛ぶ方向）
    @State private var flyOffsets: [GamePickerSelection: CGSize] = [:]

    /// フリックと判定する最低速度（pt/s）
    private let flickSpeedThreshold: CGFloat = 300

    /// 自動デモアニメの世代番号。手動操作時にインクリメントしてデモを停止する
    @State private var demoGeneration: Int = 0

    // MARK: - Logo Splash State

    // ← 変更可：何ループごとにロゴを挟むか（現在：5回）
    @State private var loopCount:      Int    = 0
    @State private var showLogoSplash: Bool   = false
    @State private var ringAngle:      Double = 0

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {

            // ── アニメーションカード ──────────────────────────
            ZStack {
                DS.cardShadow()
                ZStack {
                    if showLogoSplash {
                        // ── FDL ロゴスプラッシュ ──────────────
                        ZStack {
                            Image("fdl-logo-mark")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 165, height: 165)   // ← 変更可
                            Image("fdl-logo-ring")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 175, height: 175)   // ← 変更可
                                .blendMode(.multiply)             // 白を透過
                                .rotationEffect(.degrees(ringAngle))
                                .onAppear {
                                    withAnimation(
                                        .linear(duration: 11)     // ← 変更可：回転速度（秒/周）
                                        .repeatForever(autoreverses: false)
                                    ) { ringAngle = -360 }        // 負値 = 左回転
                                }
                                .onDisappear { ringAngle = 0 }
                        }
                        .transition(.opacity)

                    } else if showTen {
                        Text("10")
                            .font(.system(size: 130, weight: .bold, design: .rounded))
                            .foregroundStyle(DS.primary)
                            .scaleEffect(tenScale)
                        Text("✨")
                            .font(.system(size: 26))
                            .offset(x: 74, y: -62 + sparkOffsetY)
                            .opacity(sparkOpacity)
                    } else {
                        Text("\(centerNumber)")
                            .font(.system(size: 130, weight: .bold, design: .rounded))
                            .foregroundStyle(DS.primary)
                            .opacity(incomingNumber > 0 ? 1.0 : 0.0)
                        if incomingNumber > 0 {
                            HStack(spacing: 6) {
                                Text("\(incomingNumber)")
                                    .font(.system(size: 90, weight: .bold, design: .rounded))
                                    .foregroundStyle(DS.accent)
                                if showPlus {
                                    Text("+")
                                        .font(.system(size: 72, weight: .medium, design: .rounded))
                                        .foregroundStyle(DS.muted)
                                        .transition(.opacity)
                                }
                            }
                            .offset(x: incomingOffsetX - 100)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 200)
            .padding(.horizontal, 24)
            .padding(.top, 12)
            .padding(.bottom, 20)

            // ── ハイスコア表示（解放後のみ）────────────────────
            if viewModel.isHighScoreUnlocked {
                HStack(spacing: 8) {
                    Text("🏆").font(.system(size: 20))
                    Text("title_high_score_label")
                        .font(.system(size: 16, weight: .medium, design: .rounded))
                        .foregroundStyle(DS.muted)
                    Text("\(viewModel.blitzHighScore)")
                        .font(.system(size: 24, weight: .black, design: .rounded))
                        .foregroundStyle(DS.accent)
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: DS.sectionRadius)
                        .fill(DS.card)
                        .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 3)
                )
                .padding(.bottom, 16)
            }

            // ── ゲーム選択グリッド ────────────────────────────
            LazyVGrid(
                columns: [GridItem(.flexible()), GridItem(.flexible())],
                spacing: 12
            ) {
                ForEach(Array(visibleGames.enumerated()), id: \.element) { index, game in
                    GamePickerTile(
                        game:      game,
                        flyOffset: flyOffsets[game] ?? .zero
                    ) {
                        onSelectGame(game)
                    } onFlick: { translation, velocity in
                        handleFlick(
                            game:           game,
                            visibleIndex:   index,
                            translation:    translation,
                            velocity:       velocity
                        )
                    }
                }
            }
            // ← 変更可：グリッド再配置アニメ（スワップの半速に合わせて response を 0.80 に）
            .animation(.spring(response: 0.80, dampingFraction: 0.8), value: visibleGames)
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
        .onAppear {
            loopGeneration += 1
            runTitleLoop(generation: loopGeneration)

            // ← 変更可：初回デモ開始までの待機時間（秒）
            scheduleDemo(delay: 2.5)
        }
    }

    // MARK: - Visible Games

    private var visibleGames: [GamePickerSelection] {
        let all = rankManager.sortedGames.filter { $0 != .blitz || viewModel.isBlitzUnlocked }
        return Array(all.prefix(6))
    }

    // MARK: - Demo Animation

    /// デモを（再）スケジュールする。
    /// 手動操作後も delay 秒の無操作が続けば自動デモが再開される。
    /// demoGeneration をインクリメントすることで古い世代のコールバックを無効化する。
    private func scheduleDemo(delay: Double) {
        demoGeneration += 1
        let gen = demoGeneration
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            runDemoLoop(generation: gen)
        }
    }

    /// スワップデモとフライデモをランダムで切り替えながらループする。
    private func runDemoLoop(generation: Int) {
        guard generation == demoGeneration else { return }
        guard visibleGames.count >= 2     else { return }

        if Bool.random() {
            runDemoSwap(generation: generation)
        } else {
            runDemoFly(generation: generation)
        }
    }

    /// 右下2枚を入れ替えて戻すデモ。
    /// swap → 1.4秒後に swap back → 4秒後に次のデモへ。
    private func runDemoSwap(generation: Int) {
        let games      = visibleGames
        let lastGame   = games[games.count - 1]
        let secondLast = games[games.count - 2]

        guard let si = rankManager.sortedGames.firstIndex(of: lastGame),
              let sj = rankManager.sortedGames.firstIndex(of: secondLast) else { return }

        // ← 変更可：デモスワップ速度（response: 0.70 = 手動の半速）
        withAnimation(.spring(response: 0.70, dampingFraction: 0.75)) {
            rankManager.swap(at: si, with: sj)
        }

        // ← 変更可：swap back までの待機時間（秒）
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
            guard generation == self.demoGeneration else { return }
            guard let si2 = self.rankManager.sortedGames.firstIndex(of: lastGame),
                  let sj2 = self.rankManager.sortedGames.firstIndex(of: secondLast) else { return }
            withAnimation(.spring(response: 0.70, dampingFraction: 0.75)) {
                self.rankManager.swap(at: si2, with: sj2)
            }
            // ← 変更可：次のデモまでの待機時間（秒）
            DispatchQueue.main.asyncAfter(deadline: .now() + 4.0) {
                self.runDemoLoop(generation: generation)
            }
        }
    }

    /// 右下タイルを画面外に飛ばして末尾送りするデモ。
    /// 隠しゲームがあれば新タイルがスライドインして「入れ替わり」を見せられる。
    private func runDemoFly(generation: Int) {
        let games    = visibleGames
        let lastGame = games[games.count - 1]

        // ← 変更可：デモフライ方向（右端タイルなので右へ）
        let flyDir = CGSize(width: 600, height: 0)

        // ← 変更可：デモフライ速度（duration: 0.44 = 手動の半速）
        withAnimation(.easeIn(duration: 0.44)) {
            flyOffsets[lastGame] = flyDir
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.50) {
            guard generation == self.demoGeneration else { return }

            let allVisible    = rankManager.sortedGames.filter { $0 != .blitz || viewModel.isBlitzUnlocked }
            let hasHiddenGame = allVisible.count > 6

            flyOffsets.removeValue(forKey: lastGame)
            if hasHiddenGame {
                // ← 変更可：新タイルのスライドイン速度（response: 0.80 = 手動の半速）
                withAnimation(.spring(response: 0.80, dampingFraction: 0.75)) {
                    rankManager.throwToBottom(lastGame)
                }
            } else {
                rankManager.throwToBottom(lastGame)
            }

            // ← 変更可：フライ後、次のデモまでの待機時間（秒）
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                self.runDemoLoop(generation: generation)
            }
        }
    }

    // MARK: - Flick Handling

    private func handleFlick(
        game:         GamePickerSelection,
        visibleIndex: Int,
        translation:  CGSize,
        velocity:     CGSize
    ) {
        let speed = sqrt(velocity.width * velocity.width + velocity.height * velocity.height)
        guard speed > flickSpeedThreshold else { return }

        // 手動操作でデモを一時停止し、5秒後に再開する
        // ← 変更可：無操作からデモ再開までの待機時間（秒）
        scheduleDemo(delay: 5.0)

        let isHorizontal = abs(translation.width) > abs(translation.height)
        let count        = visibleGames.count
        let neighborVI:  Int?

        if isHorizontal {
            neighborVI = translation.width > 0
                ? ((visibleIndex % 2 == 0 && visibleIndex + 1 < count) ? visibleIndex + 1 : nil)
                : ((visibleIndex % 2 == 1)                              ? visibleIndex - 1 : nil)
        } else {
            neighborVI = translation.height > 0
                ? ((visibleIndex + 2 < count) ? visibleIndex + 2 : nil)
                : ((visibleIndex >= 2)         ? visibleIndex - 2 : nil)
        }

        if let nvi = neighborVI {
            let neighborGame = visibleGames[nvi]
            if let si = rankManager.sortedGames.firstIndex(of: game),
               let sj = rankManager.sortedGames.firstIndex(of: neighborGame) {
                // ← 変更可：スワップアニメ速度（response: 0.70 = 旧 0.35 の半速）
                withAnimation(.spring(response: 0.70, dampingFraction: 0.75)) {
                    rankManager.swap(at: si, with: sj)
                }
            }
        } else {
            let flyDir: CGSize
            if isHorizontal {
                flyDir = translation.width > 0
                    ? CGSize(width: 600, height: 0)
                    : CGSize(width: -600, height: 0)
            } else {
                flyDir = translation.height > 0
                    ? CGSize(width: 0, height: 600)
                    : CGSize(width: 0, height: -600)
            }

            SoundManager.shared.vibrate()
            // ← 変更可：飛び出しアニメ速度（duration: 0.44 = 旧 0.22 の半速）
            withAnimation(.easeIn(duration: 0.44)) {
                flyOffsets[game] = flyDir
            }
            // flyOffset 完了後にグリッド再配置（待機時間も飛び出し速度に合わせて延長）
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.50) {
                let allVisible  = rankManager.sortedGames.filter { $0 != .blitz || viewModel.isBlitzUnlocked }
                let hasHiddenGame = allVisible.count > 6

                flyOffsets.removeValue(forKey: game)
                if hasHiddenGame {
                    // ← 変更可：throwToBottom 後のグリッド再配置速度（response: 0.80 = 旧 0.40 の半速）
                    withAnimation(.spring(response: 0.80, dampingFraction: 0.75)) {
                        rankManager.throwToBottom(game)
                    }
                } else {
                    rankManager.throwToBottom(game)
                }
            }
        }
    }

    // MARK: - Title Animation

    private func runTitleLoop(generation: Int) {
        guard generation == loopGeneration else { return }
        resetState()
        let n = Int.random(in: 1...9)
        centerNumber = n

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            guard generation == self.loopGeneration else { return }
            self.incomingNumber = 10 - n
            withAnimation(.easeInOut(duration: 1.0)) { self.incomingOffsetX = 0 }

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                guard generation == self.loopGeneration else { return }
                withAnimation(.easeInOut(duration: 0.35)) { self.showPlus = true }

                DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) {
                    guard generation == self.loopGeneration else { return }
                    withAnimation(.easeInOut(duration: 0.28)) {
                        self.showTen = true; self.sparkOpacity = 1.0
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                        guard generation == self.loopGeneration else { return }
                        withAnimation(.easeInOut(duration: 0.28)) { self.tenScale = 1.08 }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.28) {
                            guard generation == self.loopGeneration else { return }
                            withAnimation(.easeInOut(duration: 0.28)) { self.tenScale = 1.0 }
                        }
                    }
                    withAnimation(.easeInOut(duration: 0.8)) {
                        self.sparkOffsetY = -28; self.sparkOpacity = 0.0
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                        guard generation == self.loopGeneration else { return }
                        withAnimation(.easeInOut(duration: 0.35)) {
                            self.showTen = false; self.resetState()
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
                            self.loopCount += 1
                            // ← 変更可：何ループごとにロゴを挟むか（現在：5回）
                            if self.loopCount % 5 == 0 {
                                self.runLogoSplash(generation: generation)
                            } else {
                                self.runTitleLoop(generation: generation)
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Logo Splash

    private func runLogoSplash(generation: Int) {
        guard generation == loopGeneration else { return }
        withAnimation(.easeInOut(duration: 0.5)) { showLogoSplash = true }

        // ← 変更可：ロゴ表示時間（秒）
        DispatchQueue.main.asyncAfter(deadline: .now() + 13.0) {
            guard generation == self.loopGeneration else { return }
            withAnimation(.easeInOut(duration: 0.5)) { self.showLogoSplash = false }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                self.runTitleLoop(generation: generation)
            }
        }
    }

    private func resetState() {
        incomingOffsetX = offScreenLeading; showPlus = false; showTen = false
        tenScale = 1.0; sparkOpacity = 0.0; sparkOffsetY = 0; incomingNumber = 0
    }
}
