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
    /// .zero 以外のとき、そのタイルはフリック方向に飛び出してグリッド外に消える
    @State private var flyOffsets: [GamePickerSelection: CGSize] = [:]

    /// フリックと判定する最低速度（pt/s）
    private let flickSpeedThreshold: CGFloat = 300

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {

            // ── アニメーションカード ──────────────────────────
            ZStack {
                DS.cardShadow()
                ZStack {
                    if showTen {
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
            // blitz は isBlitzUnlocked が true のときだけ visibleGames に含める。
            // 解放時はアニメーション付きでグリッドに出現する。
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
            // visibleGames が変わるたびにスプリングアニメーションでグリッドを再配置する
            // blitz 解放時もアニメーション付きで自然にタイルが出現する
            .animation(.spring(response: 0.4, dampingFraction: 0.8), value: visibleGames)
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
        .onAppear {
            loopGeneration += 1
            runTitleLoop(generation: loopGeneration)
        }
    }

    // MARK: - Visible Games

    /// 現在表示すべきゲームリスト。
    /// blitz は isBlitzUnlocked が true のときのみ含める。
    // 表示上限は6枚（3行×2列）。7枚目以降は末尾送り操作で循環させる。
    private var visibleGames: [GamePickerSelection] {
        let all = rankManager.sortedGames.filter { $0 != .blitz || viewModel.isBlitzUnlocked }
        return Array(all.prefix(6))
    }

    // MARK: - Flick Handling

    /// フリックジェスチャーを受け取り、「隣と入れ替え」か「末尾に送る」かを判定する。
    /// visibleGames のインデックスを使って隣を探し、
    /// sortedGames のインデックスに変換して rankManager に渡す。
    private func handleFlick(
        game:         GamePickerSelection,
        visibleIndex: Int,
        translation:  CGSize,
        velocity:     CGSize
    ) {
        let speed = sqrt(velocity.width * velocity.width + velocity.height * velocity.height)
        guard speed > flickSpeedThreshold else { return }

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
            // 隣のタイルと入れ替え
            // visibleGames のインデックス → sortedGames のインデックスに変換してから swap する
            let neighborGame = visibleGames[nvi]
            if let si = rankManager.sortedGames.firstIndex(of: game),
               let sj = rankManager.sortedGames.firstIndex(of: neighborGame) {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                    rankManager.swap(at: si, with: sj)
                }
            }
        } else {
            // グリッド端 → フリック方向に飛び出して末尾に送る
            // フリック方向をそのまま飛び出し方向にする（上フリックは上へ、右フリックは右へ）
            // 上端タイルを上フリックするとアニメカードを通過して画面外に消える（意図的な仕様）
            let flyDir: CGSize
            if isHorizontal {
                flyDir = translation.width > 0
                    ? CGSize(width: 600, height: 0)   // 右へ飛び出す
                    : CGSize(width: -600, height: 0)  // 左へ飛び出す
            } else {
                flyDir = translation.height > 0
                    ? CGSize(width: 0, height: 600)   // 下へ飛び出す
                    : CGSize(width: 0, height: -600)  // 上へ飛び出す（アニメカードを通過）
            }

            SoundManager.shared.vibrate()
            withAnimation(.easeIn(duration: 0.22)) {
                flyOffsets[game] = flyDir
            }
            // flyOffset アニメーション完了後にグリッドを再配置する
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                // 7枚目以降が控えているか確認する。
                // 控えがある → スプリングで新タイルを滑り込ませる。
                // 6枚丁度 → アニメなしで即座に並び替える。
                // （スプリングをかけると末尾送りしたタイルが「入れ替わる」ように見えるため）
                let allVisible = rankManager.sortedGames.filter { $0 != .blitz || viewModel.isBlitzUnlocked }
                let hasHiddenGame = allVisible.count > 6

                // flyOffset と throwToBottom を同一レンダリングフレームで処理し、
                // タイルが元位置に一瞬戻るフラッシュを防ぐ
                flyOffsets.removeValue(forKey: game)
                if hasHiddenGame {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) {
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
                            self.runTitleLoop(generation: generation)
                        }
                    }
                }
            }
        }
    }

    private func resetState() {
        incomingOffsetX = offScreenLeading; showPlus = false; showTen = false
        tenScale = 1.0; sparkOpacity = 0.0; sparkOffsetY = 0; incomingNumber = 0
    }
}
