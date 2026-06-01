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
//
//  ★ このファイルの全体像 ★
//    CoinDropView（ルート）
//      ├ CDTitleView   … ゲーム前のタイトル・説明画面
//      ├ CDPlayingView … ゲーム中（SpriteKit + HUD）
//      ├ CDResultView  … ゲーム後のリザルト画面
//      └ CoinChip      … SwiftUI 上に描画する小さなコインパーツ（共用）
//
//  ★ SpriteKit と SwiftUI の共存について ★
//    このゲームは物理演算（コインの落下・衝突）に SpriteKit を使い、
//    スコア表示・ボタンなどの UI は SwiftUI で重ねて描いています。
//    SpriteView が SpriteKit シーンを SwiftUI の世界に埋め込む橋渡し役です。

import SwiftUI
import SpriteKit

// MARK: - CoinDropView
//
// ゲーム全体のルートとなるビュー。
// 「今どの状態か」を VM の gameState で判断し、対応する子ビューに切り替える。
//
// ★ @State について ★
//   @State は「このビューが自分で持つ状態」を宣言するプロパティラッパーです。
//   値が変わると SwiftUI が自動でビューを再描画してくれます。
//   viewModel は @Observable マクロで監視され、scene は SpriteKit シーンの参照を保持します。

struct CoinDropView: View {

    /// ゲームのスコア・状態・画面遷移を管理するViewModel
    @State private var viewModel = CoinDropViewModel()
    /// 現在表示中の SpriteKit シーン（nil = まだ生成されていない）
    @State private var scene: CoinDropScene?

    var body: some View {
        // Group でラップすることで switch の各 case に .animation を一括適用できる
        Group {
            switch viewModel.gameState {
            case .title:    CDTitleView(viewModel: viewModel)
            case .playing:  CDPlayingView(viewModel: viewModel, scene: $scene)
            case .finished: CDResultView(viewModel: viewModel, scene: $scene)
            }
        }
        // 画面切り替え時にフェードイン/アウトのアニメーションをかける
        .animation(.easeInOut(duration: 0.3), value: viewModel.gameState)
        // 画面を離れた（タイトルに戻るなど）ときにシーンを一時停止してCPU負荷を下げる
        .onDisappear { scene?.isPaused = true }
    }
}

// MARK: - CDTitleView
//
// ゲーム開始前のタイトル画面。
// 遊び方の説明・合体早見表・ハイスコア・スタートボタンを表示する。
//
// ★ private について ★
//   このファイル内だけで使う部品に private を付けると、
//   外部から誤って参照される心配がなくなりコードの意図が明確になります。

private struct CDTitleView: View {
    /// 画面表示に必要なデータを VM から参照する（スコアなど）
    var viewModel: CoinDropViewModel

    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            // ── 遊び方カード ──────────────────────────────────
            // Label は「アイコン + テキスト」を横並びで表示する SwiftUI のコンポーネント
            VStack(alignment: .leading, spacing: 12) {
                Label("How to Play", systemImage: "hand.draw.fill")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(DS.muted)

                // 各行はヘルパーメソッド howToRow にまとめている（重複を避けるため）
                howToRow("👆", "Drag coins to move them")
                howToRow("✨", "Same coins stick together and merge")
                howToRow("💵", "50¢ + 50¢ makes $1")
                howToRow("🎯", "Collect up to $10 = MAKE10!")
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            // DS.card はアプリ共通のカード背景色（DesignSystem.swift で定義）
            .background(DS.card, in: RoundedRectangle(cornerRadius: DS.sectionRadius))
            .padding(.horizontal, 24)

            // ── コインの合体早見表 ─────────────────────────────
            // 「1¢ × 5 → 5¢」のような合体ルールを一覧で示すセクション
            VStack(spacing: 8) {
                mergeRow([.penny, .penny, .penny, .penny, .penny], into: .nickel)
                mergeRow([.nickel, .nickel], into: .dime)
                mergeRow([.dime, .dime, .dime, .dime, .dime], into: .halfDollar)
                mergeRow([.quarter, .quarter], into: .halfDollar)
                // into: nil → 最終合体（50¢ × 2 → $1）
                mergeRow([.halfDollar, .halfDollar], into: nil)
            }
            .padding(14)
            .frame(maxWidth: .infinity)
            .background(DS.card, in: RoundedRectangle(cornerRadius: DS.sectionRadius))
            .padding(.horizontal, 24)

            // ── ハイスコア（スコアがあるときだけ表示）─────────
            // viewModel.highScore が 0 の場合（初プレイ）はこのブロック自体を表示しない
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

            // ── スタートボタン ────────────────────────────────
            Button {
                SoundManager.shared.vibrate()   // 触覚フィードバック
                SoundManager.shared.playTap()   // タップ音
                viewModel.startGame()           // VM に「ゲーム開始」を伝える
            } label: {
                Text("ゲームスタート")
                    .font(.system(size: 26, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
                    .background(
                        RoundedRectangle(cornerRadius: DS.btnRadius)
                            .fill(DS.primary)
                            // shadow でボタンに立体感を与える
                            .shadow(color: DS.primary.opacity(0.35), radius: 8, x: 0, y: 4)
                    )
            }
            // .plain にしないとデフォルトのボタン装飾（青いハイライトなど）が付く
            .buttonStyle(.plain)
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
    }

    /// 遊び方の1行（アイコン + 説明文）を生成するヘルパー
    /// LocalizedStringKey を使うことで多言語対応（xcstrings）が自動で機能する
    private func howToRow(_ icon: String, _ text: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(icon).font(.system(size: 18))
            Text(text)
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .foregroundStyle(DS.textPrimary)
        }
    }

    /// 「コイン × N → 合体後コイン（または $1）」の1行を生成するヘルパー
    /// - Parameters:
    ///   - from: 合体前のコイン種リスト（例: [.penny, .penny, .penny, .penny, .penny]）
    ///   - into: 合体後のコイン種。nil のとき「$1」と表示する
    private func mergeRow(_ from: [CoinType], into: CoinType?) -> some View {
        HStack(spacing: 6) {
            // ForEach で from 配列を1枚ずつ CoinChip として表示
            // id: \.offset で配列の順番をIDにしている（同種コインが重複するため）
            ForEach(Array(from.enumerated()), id: \.offset) { _, c in
                CoinChip(type: c, size: 22)
            }
            // → の矢印アイコン
            Image(systemName: "arrow.right")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(DS.muted)
            // 合体先のコインを表示。nil（最終合体）のときは "$1" テキストにする
            if let into {
                CoinChip(type: into, size: 26)
            } else {
                Text("$1")
                    .font(.system(size: 16, weight: .black, design: .rounded))
                    .foregroundStyle(DS.gold)
            }
            Spacer()  // 左寄せにするための余白
        }
    }
}

// MARK: - CDPlayingView
//
// ゲームプレイ中の画面。
// SpriteKit フィールド（物理演算）を全画面に敷き、
// その上に SwiftUI の HUD（スコア・タイマー・次コイン）を重ねる構成。
//
// ★ @Binding について ★
//   @Binding は「親から渡された @State の参照」です。
//   scene は CoinDropView が持ち、ここでは読み書きだけを委託されています。
//   Binding にすることで CDPlayingView と CDResultView が同じ scene を共有できます。

private struct CDPlayingView: View {
    var viewModel: CoinDropViewModel
    /// 親の CoinDropView が持つ scene への参照（$ を付けて Binding として受け取る）
    @Binding var scene: CoinDropScene?

    var body: some View {
        // ZStack で SpriteKit 画面と HUD を重ねる
        // alignment: .top → HUD を画面上部に固定する
        ZStack(alignment: .top) {

            // ── SpriteKit フィールド（全画面）────────────────
            GeometryReader { _ in
                // SpriteView は SpriteKit の SKScene を SwiftUI に埋め込むコンポーネント
                // scene ?? ... は scene が nil のときのフォールバック（通常は onAppear で設定済み）
                SpriteView(
                    scene: scene ?? CoinDropScene(size: CGSize(width: 390, height: 820)),
                    options: [.allowsTransparency]  // 背景透過を許可（DS.bg がそのまま見える）
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .ignoresSafeArea()  // ノッチ・Dynamic Island 領域まで広げる
            }

            // ── HUD（スコア・残り時間・次のコイン）────────────
            // SpriteKit の上に SwiftUI ビューを重ねることで、
            // 物理演算はそのままにUIだけ Swift らしく書ける
            VStack(spacing: 8) {
                HStack {

                    // スコア（左）
                    VStack(alignment: .leading, spacing: 0) {
                        Text("SCORE")
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .foregroundStyle(DS.muted)
                        Text("$\(viewModel.score)")
                            .font(.system(size: 30, weight: .black, design: .rounded))
                            .foregroundStyle(DS.primary)
                    }

                    Spacer()

                    // 次に落ちてくるコインのプレビュー（中央）
                    HStack(spacing: 6) {
                        Text("NEXT")
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundStyle(DS.muted)
                        CoinChip(type: viewModel.nextCoin, size: 30)
                    }

                    Spacer()

                    // 残り時間（右）
                    VStack(alignment: .trailing, spacing: 0) {
                        Text("TIME")
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .foregroundStyle(DS.muted)
                        Text("\(viewModel.displaySeconds)")
                            .font(.system(size: 30, weight: .black, design: .rounded))
                            // 残り10秒以下になったら警告色（赤）に切り替える
                            .foregroundStyle(viewModel.displaySeconds <= 10 ? DS.gaugeWarn : DS.textPrimary)
                            .monospacedDigit()  // 数字が変わっても幅が変わらない等幅フォントにする
                    }
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 10)
                .background(
                    // 半透明の角丸カードでHUDを浮かせる
                    RoundedRectangle(cornerRadius: DS.sectionRadius)
                        .fill(DS.card.opacity(0.92))
                        .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 3)
                )
                .padding(.horizontal, 16)
                .padding(.top, 6)
            }
        }
        // ビューが画面に表示された瞬間に呼ばれる
        .onAppear {
            if let existing = scene {
                // ── 再スタート（scene が既にある場合）─────────
                // シーンを作り直すと didMove が再呼び出しされて壁が重複するため、
                // 既存シーンを再利用して resetGame() だけ呼ぶ
                existing.isPaused = false
                existing.resetGame()
            } else {
                // ── 初回起動（scene がまだない場合）───────────
                // コールバックを「先に」設定してから scene に代入する。
                // 代入と同時に didMove が走るため、先に繋いでおかないと
                // 最初のイベントを取りこぼす可能性がある。
                let newScene = CoinDropScene(size: CGSize(width: 390, height: 820))
                newScene.scaleMode = .aspectFit   // 端末サイズに合わせてフィットさせる

                // Scene → VM へのコールバックを登録（クロージャで橋渡し）
                newScene.onScoreChanged    = { viewModel.updateScore($0) }
                newScene.onSecondsChanged  = { viewModel.updateSeconds($0) }
                newScene.onNextCoinChanged = { viewModel.updateNextCoin($0) }
                newScene.onGameOver        = { viewModel.gameOver(reason: $0) }

                scene = newScene  // ここで SpriteView が描画を開始する（didMove が走る）

                // didMove（地形構築）が完了した次のRunLoopでゲームを開始する
                // async にしないと didMove 前に resetGame が呼ばれてしまう
                DispatchQueue.main.async { newScene.resetGame() }
            }
        }
    }
}

// MARK: - CDResultView
//
// ゲーム終了後のリザルト画面。
// 終了理由（時間切れ / 溢れ）・スコア・ハイスコアを表示し、
// 「もう一度」か「タイトルへ戻る」を選べる。

private struct CDResultView: View {
    var viewModel: CoinDropViewModel
    /// Playing 画面から引き継いだ scene（タイトルへ戻るときに nil に戻す）
    @Binding var scene: CoinDropScene?

    /// 終了理由を多言語テキストに変換する計算プロパティ
    /// LocalizedStringKey を返すことで xcstrings の翻訳が自動で適用される
    private var reasonText: LocalizedStringKey {
        switch viewModel.gameOverReason {
        case .timeUp:   return "Time's Up!"
        case .overflow: return "Field Full!"
        }
    }

    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            // ── 達成バナー（MAKE10 / 新記録 / 何もなし）────────
            // isPerfect（$10達成）が優先、次いで isNewRecord（自己ベスト更新）
            if viewModel.isPerfect {
                Text("🎉 MAKE10! 🎉")
                    .font(.system(size: 24, weight: .black, design: .rounded))
                    .foregroundStyle(DS.gold)
                    .padding(.horizontal, 24).padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: DS.sectionRadius)
                            .fill(DS.gold.opacity(0.14))
                    )
                    // .transition で表示・非表示時にアニメーションをかける
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

            // 終了理由テキスト（"Time's Up!" or "Field Full!"）
            Text(reasonText)
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundStyle(DS.muted)

            // ── スコア表示カード ──────────────────────────────
            VStack(spacing: 4) {
                Text("Your Score")
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .foregroundStyle(DS.muted)
                Text("$\(viewModel.score)")
                    .font(.system(size: 60, weight: .black, design: .rounded))
                    .foregroundStyle(DS.primary)
                    // 数字が大きくなっても枠からはみ出さないよう最小0.5倍まで縮小許可
                    .minimumScaleFactor(0.5)
            }
            .padding(.vertical, 20).frame(maxWidth: .infinity)
            .background(DS.card, in: RoundedRectangle(cornerRadius: DS.sectionRadius))
            .padding(.horizontal, 24)

            // ── ハイスコア表示 ────────────────────────────────
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

            // ── ボタン群 ──────────────────────────────────────
            VStack(spacing: 12) {

                // もう一度プレイする
                Button {
                    SoundManager.shared.vibrate()
                    SoundManager.shared.playTap()
                    viewModel.startGame()  // .playing 状態へ戻る（CDPlayingView が再スタートを処理）
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

                // タイトルへ戻る
                Button {
                    SoundManager.shared.vibrate()
                    scene?.isPaused = true  // シーンを一時停止（CPUを節約）
                    scene = nil             // シーン参照を解放（次回は新規作成になる）
                    withAnimation(.easeInOut(duration: 0.3)) {
                        viewModel.returnToTitle()  // .title 状態へ戻る
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
//
// SpriteKit ではなく SwiftUI で描画するコインの「見た目だけ」のパーツ。
// タイトル画面の合体早見表・HUD の NEXT 表示・リザルト画面などで再利用される。
// 物理演算は持たず、純粋にデザイン目的のコンポーネント。

private struct CoinChip: View {
    /// 表示するコインの種類（色・ラベルはこれで決まる）
    let type: CoinType
    /// コインの直径（ポイント）。デフォルト 28pt
    var size: CGFloat = 28

    var body: some View {
        // ZStack でコイン本体・縁取り・ラベルを重ねる
        ZStack {
            Circle()
                .fill(type.color)  // コイン種ごとの色（CoinType.color で定義）
                // overlay で縁取りを内側に重ねる（別ノードを使うより軽量）
                .overlay(Circle().stroke(.black.opacity(0.18), lineWidth: 1.5))
            Text(type.label)
                .font(.system(size: size * 0.42, weight: .black, design: .rounded))
                // UIColor → Color の変換（SpriteKit 側の色定義をそのまま流用）
                .foregroundStyle(Color(uiColor: type.labelUIColor))
                .minimumScaleFactor(0.5)  // コインが小さくてもラベルが見えるように縮小許可
        }
        .frame(width: size, height: size)
    }
}
