//
//  TitleView.swift
//  FDL-TenBlitz
//
//  Created by 空飛ぶ研究室(FlyingDevLab) on 2026/03/08.
//

// タイトル画面のルートビュー。
// アニメーションカード・ハイスコア・ゲーム選択グリッドを管理する。
//
// ★ このファイルの構成 ★
//   TitleView（親）
//     ├ アニメーションカード … 「n + (10-n) = 10」をループアニメで表示
//     │                        5ループごとに FDL ロゴスプラッシュを挟む
//     ├ ハイスコア表示       … isHighScoreUnlocked が true のときのみ表示
//     └ ゲーム選択グリッド   … GamePickerTile を LazyVGrid で2列に並べる
//
// 役割分担:
//   - GamePickerTile (GamePickerComponents.swift) : タップ/フリックの「判定」
//   - TitleView（このファイル）                    : フリックの「処理」（スワップ・吹き飛ばし・デモ）
//   - GameRankManager                              : 並び順の永続化
//   - MakeTenContentView                           : タイル選択後の画面遷移・ゲーム開始
//
// ★ 旧バージョンからの変更点 ★
//   「30びょう」「10びょう」の ModeButton と「その他ゲーム」ボタンを廃止し、
//   全ゲームを統一サイズの GamePickerTile で2列グリッドに並べた。
//   フリック操作で並び替えができ、並び順は GameRankManager が UserDefaults に永続化する。
//   blitz（10びょう）は isBlitzUnlocked が true になるまで非表示にする。
//
// このファイルでは「世代番号パターン」を多用している（loopGeneration / demoGeneration）。
// パターンの解説は GameViewModel.swift を参照。

import SwiftUI

// MARK: - TitleView

struct TitleView: View {

    // MARK: 依存（呼び出し側から渡すパラメータ）

    var viewModel:    GameViewModel
    /// タイルがタップされたときに呼ばれるコールバック。
    /// MakeTenContentView が画面遷移・ゲーム開始を担う。
    var onSelectGame: (GamePickerSelection) -> Void

    /// 流れてくる数字の初期X位置（画面外左）。resetState() で毎ループここに戻す。
    private let offScreenLeading: CGFloat = -220

    // MARK: アニメーション状態

    /// 中央に表示する数字（1〜9のランダム）。
    @State private var centerNumber:    Int     = Int.random(in: 1...9)
    /// 左から流れてくる相方の数字（10 - centerNumber）。0 のときは非表示。
    @State private var incomingNumber:  Int     = 0
    /// 流れてくる数字の現在X位置。-220（画面外）→ 0（定位置）へアニメする。
    @State private var incomingOffsetX: CGFloat = -220
    /// 「+」記号の表示フラグ。数字が定位置に着いてから表示する。
    @State private var showPlus:        Bool    = false
    /// 「10」の表示フラグ。true の間は数式の代わりに大きな10を表示する。
    @State private var showTen:         Bool    = false
    /// 「10」のパルス演出用スケール（1.0 → 1.08 → 1.0）。
    @State private var tenScale:        CGFloat = 1.0
    /// ✨の不透明度。「10」の登場と同時に光って、上昇しながら消える。
    @State private var sparkOpacity:    Double  = 0.0
    /// ✨のY方向オフセット。0 → -28 へ上昇する。
    @State private var sparkOffsetY:    CGFloat = 0
    /// タイトルループの世代番号。画面再表示時に古いループのコールバックを無効化する。
    @State private var loopGeneration:  Int     = 0

    // MARK: ゲームグリッド状態

    /// ゲームタイルの並び順を管理する（UserDefaults に永続化）。
    @State private var rankManager = GameRankManager()
    /// 末尾送り演出中のタイルのフライオフセット（キー: ゲーム、値: 飛ぶ方向）。
    @State private var flyOffsets: [GamePickerSelection: CGSize] = [:]

    /// フリックと判定する最低速度（pt/s）。
    private let flickSpeedThreshold: CGFloat = 300   // ← 変更可

    /// 自動デモアニメの世代番号。手動操作時にインクリメントしてデモを停止する。
    @State private var demoGeneration: Int = 0

    // MARK: ロゴスプラッシュ状態

    /// タイトルループの累計回数。5の倍数のときロゴスプラッシュを挟む。
    @State private var loopCount:      Int    = 0
    /// ロゴスプラッシュの表示フラグ。
    @State private var showLogoSplash: Bool   = false
    /// ロゴ外周リングの回転角度（度）。表示中は左回転し続ける。
    @State private var ringAngle:      Double = 0

    // MARK: body

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
                                // blendMode(.multiply): 重なった色を「掛け算」で合成するモード。
                                // 白(1.0)を掛けても下の色が変わらないため、リング画像の白背景が透過して見える
                                .blendMode(.multiply)
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
                        // ── 完成形「10」とキラキラ ─────────────
                        Text("10")
                            .font(.system(size: 130, weight: .bold, design: .rounded))
                            .foregroundStyle(DS.primary)
                            .scaleEffect(tenScale)
                        Text("✨")
                            .font(.system(size: 26))
                            .offset(x: 74, y: -62 + sparkOffsetY)
                            .opacity(sparkOpacity)
                    } else {
                        // ── 数式「n + (10-n)」の組み立て ───────
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
            // ★ LazyVGrid とは？ ★
            //   格子状にViewを並べるコンテナです。columns で列の定義を渡し、
            //   ここでは .flexible() ×2 で「等幅2列」を作っています。
            //   "Lazy" は「画面に見える分だけ生成する」という意味で、
            //   タイル数が増えてもパフォーマンスが落ちにくい仕組みです。
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

    // MARK: 表示ゲームの算出

    /// グリッドに表示するゲーム一覧。blitz は解放前は除外し、先頭6つ（2列×3行）に絞る。
    ///
    /// ⚠️ 変更注意: prefix(6) の「6」は handleFlick / runDemoFly 内の
    ///   「allVisible.count > 6」と連動している。表示数を変えるときは
    ///   3箇所すべてを同じ値に揃えること（ずれると隠しゲームの判定が壊れる）。
    private var visibleGames: [GamePickerSelection] {
        let all = rankManager.sortedGames.filter { $0 != .blitz || viewModel.isBlitzUnlocked }
        return Array(all.prefix(6))
    }

    // MARK: 自動デモアニメ

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

            // ⚠️ 変更注意: 「> 6」は visibleGames の prefix(6) と連動（詳細はそちらを参照）
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

    // MARK: フリック処理

    /// フリックの方向と速度から「隣とスワップ」か「画面外へ飛ばして末尾送り」かを決めて実行する。
    ///
    /// ★ 2列グリッドの座標の考え方 ★
    ///   visibleIndex はグリッド上の通し番号で、2列なので:
    ///     0 1      ・偶数 = 左列 / 奇数 = 右列
    ///     2 3      ・+1 / -1 = 左右の隣
    ///     4 5      ・+2 / -2 = 上下の隣
    ///   フリック方向の隣が存在すればスワップ、存在しなければ（端から外へ向かう
    ///   フリックなら）タイルを画面外へ飛ばして末尾送りにする。
    private func handleFlick(
        game:         GamePickerSelection,
        visibleIndex: Int,
        translation:  CGSize,
        velocity:     CGSize
    ) {
        // 三平方の定理で速度ベクトルの大きさを求め、しきい値未満は無視する
        let speed = sqrt(velocity.width * velocity.width + velocity.height * velocity.height)
        guard speed > flickSpeedThreshold else { return }

        // 手動操作でデモを一時停止し、5秒後に再開する
        // ← 変更可：無操作からデモ再開までの待機時間（秒）
        scheduleDemo(delay: 5.0)

        // 移動量の大きい軸をフリック方向とみなす（横長なら左右、縦長なら上下）
        let isHorizontal = abs(translation.width) > abs(translation.height)
        let count        = visibleGames.count
        let neighborVI:  Int?

        if isHorizontal {
            // 右フリック: 左列(偶数)で右隣が存在すれば +1 / 左フリック: 右列(奇数)なら -1
            neighborVI = translation.width > 0
                ? ((visibleIndex % 2 == 0 && visibleIndex + 1 < count) ? visibleIndex + 1 : nil)
                : ((visibleIndex % 2 == 1)                              ? visibleIndex - 1 : nil)
        } else {
            // 下フリック: 下の行が存在すれば +2 / 上フリック: 上の行が存在すれば -2
            neighborVI = translation.height > 0
                ? ((visibleIndex + 2 < count) ? visibleIndex + 2 : nil)
                : ((visibleIndex >= 2)         ? visibleIndex - 2 : nil)
        }

        if let nvi = neighborVI {
            // ── 隣が存在する → スワップ ──────────────────────
            let neighborGame = visibleGames[nvi]
            if let si = rankManager.sortedGames.firstIndex(of: game),
               let sj = rankManager.sortedGames.firstIndex(of: neighborGame) {
                // ← 変更可：スワップアニメ速度（response: 0.70 = 旧 0.35 の半速）
                withAnimation(.spring(response: 0.70, dampingFraction: 0.75)) {
                    rankManager.swap(at: si, with: sj)
                }
            }
        } else {
            // ── 隣が存在しない（端の外向きフリック）→ 飛ばして末尾送り ──
            // 600pt = どの端末でも画面外まで確実に出る距離
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
                // ⚠️ 変更注意: 「> 6」は visibleGames の prefix(6) と連動（詳細はそちらを参照）
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

    // MARK: タイトルアニメーション

    /// 「n + (10-n) = 10」のループアニメを1周実行し、最後に自分自身を再帰呼び出しする。
    ///
    /// ★ このアニメの時間軸 ★（asyncAfter の深いネストを読む前にこの表を見てください）
    ///   0.0秒   中央に n を配置（この時点では非表示）
    ///   0.8秒   相方の数字 (10-n) が画面外左からスライドイン（1.0秒かけて）
    ///   1.4秒   「+」がフェードイン
    ///   1.95秒  数式が「10」に切り替わり、✨が光って上昇しながら消える
    ///   2.1秒   「10」がパルス（1.0 → 1.08 → 1.0）
    ///   3.15秒  「10」がフェードアウトして状態リセット
    ///   3.6秒   ループ回数を加算し、5の倍数ならロゴスプラッシュへ、それ以外は次のループへ
    ///   ※ 各ステップの guard generation == loopGeneration は、画面遷移などで
    ///     新しいループが始まったとき、古いループの続きを止めるための世代チェック
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

    // MARK: ロゴスプラッシュ

    /// FDL ロゴ（家マーク＋回転リング）を一定時間表示してからタイトルループに戻る。
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

    // MARK: 状態リセット

    /// アニメーション用の状態を全てループ開始前の初期値に戻す。
    private func resetState() {
        incomingOffsetX = offScreenLeading; showPlus = false; showTen = false
        tenScale = 1.0; sparkOpacity = 0.0; sparkOffsetY = 0; incomingNumber = 0
    }
}
