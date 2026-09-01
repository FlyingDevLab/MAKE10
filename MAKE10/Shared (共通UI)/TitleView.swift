//
//  TitleView.swift
//  FDL-TenBlitz
//
//  Created by 空飛ぶ研究室(FlyingDevLab) on 2026/03/08.
//

// タイトル画面のルートビュー。
// アニメーションカードとゲーム選択グリッドを管理する。
//
// ★ このファイルの構成 ★
//   TitleView（親）
//     ├ アニメーションカード … 画面表示直後に FDL ロゴを 4.5 秒表示し、
//     │                        その後「n + (10-n) = 10」をループアニメで表示。
//     │                        以降 5 ループごとに 13 秒のロゴを挟む。
//     │                        左右フリックで画面外へ追い出せる（遊び要素。
//     │                        追い出した枠は空白のまま残り、数秒後に
//     │                        反対側からロゴで再登場する）
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

    /// グリッドに表示するタイル枚数（2列 × 3行）。
    /// visibleGames / runDemoFly / handleFlick の3箇所がこの値を共有する。
    private let visibleTileCount: Int = 6            // ← 変更可

    /// 自動デモアニメの世代番号。手動操作時にインクリメントしてデモを停止する。
    @State private var demoGeneration: Int = 0

    // MARK: ロゴスプラッシュ状態

    /// タイトルループの累計回数。5の倍数のときロゴスプラッシュを挟む。
    @State private var loopCount:      Int    = 0
    /// ロゴスプラッシュの表示フラグ。画面表示直後はロゴから始めるため true。
    @State private var showLogoSplash: Bool   = true
    /// ロゴ外周リングの回転角度（度）。表示中は左回転し続ける。
    @State private var ringAngle:      Double = 0

    // MARK: カード追い出し状態

    // ★ この機能は「意味のない遊び」として独立させている ★
    //   ゲームタイルのフリック（並べ替え）とは無関係で、
    //   scheduleDemo() も呼ばない。並び順にも一切影響しない。
    //
    // ★ なぜ .offset() で動かすのか ★
    //   .offset() はレイアウト計算に影響しないため、カードが画面外へ出ても
    //   VStack 上の占有スペース（高さ200）はそのまま残る。
    //   結果として「追い出した部分が空白になる」という狙い通りの見た目になり、
    //   下のグリッドが繰り上がることもない。

    /// アニメーションカードの現在オフセット。左右フリックで ±cardFlyDistance へ動かす。
    @State private var cardFlyOffset: CGSize = .zero
    /// カードが定位置に無い間（飛行中〜復帰完了まで）true。二重フリックを防ぐ。
    @State private var isCardAway:    Bool   = false

    /// カードを飛ばす距離（pt）。600 = どの端末でも確実に画面外まで出る。
    private let cardFlyDistance:  CGFloat = 600    // ← 変更可
    /// カードが画面外で待機する時間（秒）。
    private let cardAwayDuration: Double  = 4.5    // ← 変更可
    /// 復帰時のスライドイン時間（秒）。
    private let cardReturnDuration: Double = 0.5   // ← 変更可

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
            .offset(cardFlyOffset)
            // カード内は文字と画像だけで背景が無い箇所があるため、
            // 矩形全体をタッチ判定にしてどこを触ってもフリックできるようにする
            .contentShape(Rectangle())
            // タップ操作は無いので minimumDistance を持たせ、
            // 指のわずかな動きを拾わないようにする
            .gesture(
                DragGesture(minimumDistance: 10)
                    .onEnded { value in
                        handleCardFlick(
                            translation: value.translation,
                            velocity:    value.velocity
                        )
                    }
            )

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
            // ⚠️ カードを追い出したまま他ゲームへ遷移すると、@State に
            //   ±600 のオフセットが残ったままになる。世代チェックに頼らず、
            //   画面が現れるたびここで必ず定位置へ戻すこと。
            //   （これを省くと、戻ってきたときカードが画面外に取り残され、
            //     再起動するまで空白のままになる）
            cardFlyOffset = .zero
            isCardAway    = false

            loopGeneration += 1
            // 画面表示直後はロゴから始める。ロゴ終了後に runTitleLoop へ自動で移る。
            // ← 変更可：先頭ロゴの表示時間（秒）
            runLogoSplash(generation: loopGeneration, duration: 4.5)

            // ← 変更可：初回デモ開始までの待機時間（秒）
            scheduleDemo(delay: 2.5)
        }
    }

    // MARK: 表示ゲームの算出

    /// グリッドに表示するゲーム一覧。blitz は解放前は除外し、
    /// 先頭 visibleTileCount 個（2列×4行）に絞る。
    ///
    /// ⚠️ 変更注意: 表示枚数は visibleTileCount 一箇所で管理している。
    ///   handleFlick / runDemoFly の「allVisible.count > visibleTileCount」も
    ///   同じ定数を参照しているため、枚数を変えるときは定数だけを書き換えること。
    private var visibleGames: [GamePickerSelection] {
        let all = rankManager.sortedGames.filter { $0 != .blitz || viewModel.isBlitzUnlocked }
        return Array(all.prefix(visibleTileCount))
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
            // ⚠️ 後始末（flyOffsets の除去）は世代に関係なく必ず行うこと。
            //   guard の後に書くと、デモ中にユーザーが操作した場合（＝世代が進んだ場合）に
            //   タイルが画面外へ取り残され、再起動するまでグリッドに空白が残るバグになる。
            guard generation == self.demoGeneration else {
                // デモ中断時: 飛ばしかけたタイルをスプリングで元の位置へ戻す
                withAnimation(.spring(response: 0.40, dampingFraction: 0.80)) {
                    // _ = で removeValue の戻り値（取り除いた値）を明示的に捨てる。
                    // クロージャの中身が1式だけだと暗黙returnになり、
                    // withAnimation がその値を返して「結果が未使用」警告になるため。
                    _ = self.flyOffsets.removeValue(forKey: lastGame)
                }
                return
            }

            // 表示枚数より多くゲームがあれば、繰り上がる隠しタイルが存在する
            let allVisible    = rankManager.sortedGames.filter { $0 != .blitz || viewModel.isBlitzUnlocked }
            let hasHiddenGame = allVisible.count > visibleTileCount

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
    ///     6 7      （行数は visibleTileCount に応じて増減する）
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
                // 表示枚数より多くゲームがあれば、繰り上がる隠しタイルが存在する
                let allVisible  = rankManager.sortedGames.filter { $0 != .blitz || viewModel.isBlitzUnlocked }
                let hasHiddenGame = allVisible.count > visibleTileCount

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
    // MARK: カード追い出し処理

    /// アニメーションカードを左右フリックで画面外へ追い出し、数秒後に反対側から戻す。
    ///
    /// ★ 時間軸 ★
    ///   0.00秒  loopGeneration を進めて走行中のアニメを停止し、飛ばし始める
    ///   0.50秒  中身をリセットし、アニメーション無しで反対側へ瞬間移動
    ///           （以降 cardAwayDuration 秒、枠は空白のまま）
    ///   5.00秒  反対側からスライドインしつつ、ロゴ 4.5 秒から再スタート
    ///
    /// ★ なぜ中身をリセットするのか ★
    ///   飛ばした時点では数式の途中かもしれず、そのまま戻すと中途半端な状態から
    ///   再開して不自然になる。画面外で初期状態に戻し、復帰時は必ず
    ///   「ロゴ → 数式ループ」の固定シーケンスで始まるようにしている。
    ///   リセットを 0.50秒後（＝飛び切った後）に行うのは、画面内で中身が
    ///   消えるところを見せないため。
    private func handleCardFlick(translation: CGSize, velocity: CGSize) {
        // 定位置に無いときは無視する（飛行中の二重フリック防止）
        guard !isCardAway else { return }

        // 三平方の定理で速度ベクトルの大きさを求め、しきい値未満は無視する
        // （しきい値はゲームタイルと共通の flickSpeedThreshold を使う）
        let speed = sqrt(velocity.width * velocity.width + velocity.height * velocity.height)
        guard speed > flickSpeedThreshold else { return }

        // 横方向のフリックのみ受け付ける。
        // .offset() は他のビューを避けないため、上へ飛ばすとヘッダーに、
        // 下へ飛ばすとゲームグリッドに重なってしまう。
        guard abs(translation.width) > abs(translation.height) else { return }

        let toRight = translation.width > 0
        isCardAway  = true

        // 走行中のタイトルループ／ロゴスプラッシュを世代番号で停止する。
        // （多段の asyncAfter を止める手段はこれしかない）
        loopGeneration += 1
        let generation = loopGeneration

        SoundManager.shared.vibrate()

        // ← 変更可：飛び出しアニメ速度（ゲームタイルと同じ 0.44 秒）
        withAnimation(.easeIn(duration: 0.44)) {
            cardFlyOffset = CGSize(
                width:  toRight ? cardFlyDistance : -cardFlyDistance,
                height: 0
            )
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.50) {
            // 画面を離れて戻った場合は onAppear が後始末済みなので、ここは何もしない
            guard generation == self.loopGeneration else { return }

            // ① 中身を初期状態へ（画面外なので切り替わる瞬間は見えない）
            self.resetState()
            self.showLogoSplash = false
            self.loopCount      = 0

            // ② 反対側へ瞬間移動する。
            //    withAnimation を付けないことで、画面を横切って戻る動きを避ける。
            self.cardFlyOffset = CGSize(
                width:  toRight ? -self.cardFlyDistance : self.cardFlyDistance,
                height: 0
            )

            // ③ 待機後、反対側からスライドインしながらロゴで再スタート
            DispatchQueue.main.asyncAfter(deadline: .now() + self.cardAwayDuration) {
                guard generation == self.loopGeneration else { return }

                withAnimation(.easeOut(duration: self.cardReturnDuration)) {
                    self.cardFlyOffset = .zero
                }
                self.isCardAway = false

                // ← 変更可：復帰時のロゴ表示時間（秒。onAppear と同じ 4.5 秒）
                self.runLogoSplash(generation: generation, duration: 4.5)
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

    /// FDL ロゴ（家マーク＋回転リング）を duration 秒表示してからタイトルループに戻る。
    ///
    /// - Parameter duration: ロゴの表示秒数。省略時は周期表示用の 13 秒。
    ///   画面表示直後の初回のみ onAppear から短い値（4.5秒）を渡して呼ぶ。
    ///   周期呼び出し（runTitleLoop の5ループごと）は引数なしで 13 秒のまま。
    private func runLogoSplash(generation: Int, duration: Double = 13.0) {   // ← 変更可（既定の表示時間）
        guard generation == loopGeneration else { return }
        withAnimation(.easeInOut(duration: 0.5)) { showLogoSplash = true }

        DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
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

