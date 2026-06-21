//
//  PlayingView.swift
//  FDL-TenBlitz
//
//  Created by 空飛ぶ研究室(FlyingDevLab) on 2026/03/08.
//

// ゲームプレイ中の画面を構成するViewファイル。
// 問題カード・タイルグリッド・コンボリアクション・正誤マークを重ねて表示する。
// 各UIパーツはサブViewとして独立させ、PlayingViewはレイアウトのみを担う。
//
// ★ このファイルの構成 ★
//   PlayingView（親）
//     ├ ProblemCardView … 問題番号・次の問題・タイムゲージをまとめたカード
//     │   └ InlineGaugeView … タイムゲージの横バー
//     ├ TileButton       … 数字タイル（4枚）
//     │   └ TileButtonStyle … タップ時の拡大エフェクト（ButtonStyle）
//     ├ AnswerMarkView    … 正解⭕️ / 不正解❌ のフィードバック
//     └ ReactionView      … コンボ時に浮かぶ絵文字リアクション
//
// ★ なぜサブViewに分割するのか ★
//   1つの body に全部書くと再描画の範囲が広がり、パフォーマンスが悪化します。
//   また、コードが長くなって「どこが何の役割か」がわかりにくくなります。
//   サブViewに切り出すことで「このViewは○○だけを担当する」という
//   責任の分離が明確になります。

import SwiftUI

// MARK: - PlayingView

struct PlayingView: View {
    var viewModel: GameViewModel

    /// タイルを2列グリッドで並べる定義。列間隔は EmojiQuizHomeView と統一している。
    /// GridItem(.flexible()) = 利用可能な横幅を均等に分割する列。
    /// （LazyVGrid 自体の解説は TitleView.swift を参照）
    let columns = [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)]

    var body: some View {
        // ZStack でカード・タイル・リアクション・正誤マークを重ねる
        // 奥から手前の順に: VStack（カード+タイル）→ リアクション → 正誤マーク
        ZStack {
            VStack(spacing: 0) {

                // ── 問題カード ────────────────────────────────
                // 現在の問題番号・次の問題番号・タイムゲージを表示する
                ProblemCardView(
                    questionNumber:     viewModel.questionNumber,
                    nextQuestionNumber: viewModel.nextQuestionNumber,
                    timeRemaining:      viewModel.timeRemaining,
                    maxTime:            viewModel.maxTime,
                    warnThreshold:      viewModel.gaugeWarnThreshold,
                    gameMode:           viewModel.gameMode
                )
                .padding(.horizontal, 24)
                .padding(.top, 12)
                .padding(.bottom, 20)

                // ── タイルグリッド（4枚）────────────────────
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(0..<4, id: \.self) { index in
                        TileButton(
                            value:          viewModel.tiles[index],
                            // tappedTileValue がこのタイルの値と一致するとき answerMark を渡す。
                            // 一致しないタイルは nil のまま（通常色）で表示される。
                            // タイルが切り替わると値が変わり自然にハイライトが消える
                            highlightState: viewModel.tappedTileValue == viewModel.tiles[index]
                                            ? viewModel.answerMark : nil
                        ) {
                            withAnimation(.spring(response: 0.28, dampingFraction: 0.75)) {
                                viewModel.answer(viewModel.tiles[index])
                            }
                        }
                        // ★ .id("tile-{index}-{value}") の役割 ★
                        //   SwiftUI は .id() が変わったとき「別のView」として扱います。
                        //   正解後にタイルの数字が変わると、古いViewが消えて新しいViewが
                        //   .transition で指定したアニメーションで出現します。
                        //   .id() がなければ「同じViewの値が変わっただけ」と判断されて
                        //   トランジションが発火しません。
                        .id("tile-\(index)-\(viewModel.tiles[index])")
                        // asymmetric: 出現と消去に別々のアニメーションを指定する
                        // .scale(0.4) = 小さいサイズから等倍に拡大して現れる（ポップイン）
                        .transition(.asymmetric(
                            insertion: .scale(scale: 0.4).combined(with: .opacity),
                            removal:   .scale(scale: 0.4).combined(with: .opacity)
                        ))
                    }
                }
                .padding(.horizontal, 20)

                Spacer()
            }

            // ── コンボリアクション絵文字 ──────────────────────
            // viewModel.reactions の各要素を ReactionView として表示する。
            // ReactionView はアニメーション完了後に onFinished コールバックで
            // reactions 配列から自分自身を削除するよう通知する（自己完結型）
            ForEach(viewModel.reactions) { r in
                ReactionView(reaction: r) { viewModel.removeReaction(id: r.id) }
            }

            // ── 正誤マーク ──────────────────────────────────
            // viewModel.answerMark が nil でないとき（= 正解か不正解のとき）だけ表示する。
            // allowsHitTesting(false) でタッチをすり抜けさせ、
            // マーク表示中もタイルをタップできるようにしている
            if let mark = viewModel.answerMark {
                AnswerMarkView(mark: mark)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .padding(.top, 122) // カード下端(192) - マーク半高(22) ≈ 隙間中央
                    .transition(.asymmetric(
                        insertion: .scale(scale: 0.5).combined(with: .opacity),  // 小→等倍でポップイン
                        removal:   .scale(scale: 1.3).combined(with: .opacity)   // 等倍→大でポップアウト
                    ))
                    .allowsHitTesting(false)
                    .zIndex(30)  // タイルより手前・紙吹雪より奥に表示
            }
        }
        // answerMark の変化をトリガーに正誤マークのトランジションをスプリングで動かす
        // ★ .animation(value:) とは？ ★
        //   指定した値が変化したときだけアニメーションを適用するモディファイア。
        //   値を指定しない .animation() は「すべての変化」に適用されて意図しない
        //   アニメーションが起きやすいため、値を絞るこちらの形が推奨されています。
        .animation(.spring(response: 0.25, dampingFraction: 0.6), value: viewModel.answerMark)
    }
}

// MARK: - ProblemCardView

/// 現在の問題番号・次の問題番号・タイムゲージを1枚のカードにまとめて表示するView。
/// 高さを180ptに固定して、EmojiQuizHomeViewのQuizQuestionCardと高さを揃えている。
struct ProblemCardView: View {
    let questionNumber:     Int
    let nextQuestionNumber: Int
    let timeRemaining:      Double
    let maxTime:            Double
    let warnThreshold:      Double
    let gameMode:           GameMode

    /// Blitzモードは赤系、通常モードは青系で問題番号とゲージを色分けする。
    /// 計算プロパティにすることで gameMode が変わると自動で追従する。
    private var mainColor: Color { gameMode == .blitz ? DS.blitzColor : DS.primary }

    var body: some View {
        // 絵文字クイズのカードと同じ 180pt 固定
        VStack(spacing: 0) {
            Spacer(minLength: 0)

            // ── NEXT エリア（次の問題番号の予告）────────────
            // nextQuestionNumber が変わるたびに上からスライドインするトランジションを適用する
            HStack(alignment: .lastTextBaseline, spacing: 6) {
                Text("playing_next_label")
                    .font(.system(size: 11, weight: .black, design: .rounded))
                    .foregroundStyle(mainColor.opacity(0.45))
                    .tracking(1.0)  // 文字間隔を広げて「NEXT」の視認性を上げる

                // .id(nextQuestionNumber): 値の変化で .transition を発火させるためのトリック
                // （.id() の詳しい役割は PlayingView のタイルグリッドの解説を参照）
                Text("\(nextQuestionNumber)")
                    .font(.system(size: 36, weight: .bold, design: .rounded))
                    .foregroundStyle(mainColor.opacity(0.32))
                    .id(nextQuestionNumber)
                    .transition(.asymmetric(
                        insertion: .move(edge: .top).combined(with: .opacity),
                        removal:   .move(edge: .bottom).combined(with: .opacity)
                    ))
                Spacer()
                // Blitz モードのときのみ右上にモードラベルを表示する
                if gameMode == .blitz {
                    Text("playing_blitz_mode_label")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(DS.blitzColor)
                }
            }
            .padding(.horizontal, 20)

            // ── メイン数字（現在の問題番号）────────────────
            // questionNumber が変わると上からスライドインして、古い数字は下にスライドアウトする
            Text("\(questionNumber)")
                .font(.system(size: 80, weight: .bold, design: .rounded))
                .foregroundStyle(mainColor)
                .frame(maxWidth: .infinity, alignment: .center)
                .id(questionNumber)
                .transition(.asymmetric(
                    insertion: .move(edge: .top).combined(with: .opacity),
                    removal:   .move(edge: .bottom).combined(with: .opacity)
                ))

            Spacer(minLength: 0)

            // ── タイムゲージ ──────────────────────────────
            InlineGaugeView(
                timeRemaining: timeRemaining,
                maxTime:       maxTime,
                warnThreshold: warnThreshold
            )
            .padding(.horizontal, 20)
            .padding(.bottom, 14)
        }
        .frame(height: 180)
        .background(DS.cardShadow())
        // .clipShape でカードの角丸を適用し、.clipped() でコンテンツのはみ出しを防ぐ
        // ★ なぜ両方必要か ★
        //   .clipShape はこのViewの形を角丸にするが、子ビューが範囲外にレンダリングされる場合がある。
        //   .clipped() を重ねることで確実に角丸の内側だけに表示を限定できる。
        .clipShape(RoundedRectangle(cornerRadius: DS.cardRadius))
        .clipped()
    }
}

// MARK: - InlineGaugeView

/// 残り時間を横バーで表示するタイムゲージ。
/// timeRemaining が warnThreshold 以下になると色が警告色（赤系）に切り替わる。
struct InlineGaugeView: View {
    let timeRemaining: Double
    let maxTime:       Double
    let warnThreshold: Double

    /// 残り時間を maxTime に対する比率（0.0〜1.0）に変換してバーの幅に使う。
    /// 例: maxTime=30, timeRemaining=15 なら ratio=0.5（バーが半分の幅になる）
    private var ratio: CGFloat { CGFloat(timeRemaining / maxTime) }

    /// 残り時間が閾値以下になったら警告色（赤系）、それ以外は良好色（緑系）に切り替える
    private var color: Color   { timeRemaining <= warnThreshold ? DS.gaugeWarn : DS.gaugeFull }

    var body: some View {
        // GeometryReader でこのViewが表示される実際の幅を取得し、
        // geo.size.width を使ってゲージバーの幅を計算する
        // （GeometryReader の解説は ConfettiView.swift を参照）
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                // 背景トラック（薄いグレーの全幅バー）
                RoundedRectangle(cornerRadius: DS.gaugeRadius)
                    .fill(DS.gaugeBg)
                    .frame(height: 13)

                // 前景バー（残り時間に比例した幅）
                // max(0, ...) で幅が負にならないよう保護する（わずかな誤差でクラッシュしないため）
                RoundedRectangle(cornerRadius: DS.gaugeRadius)
                    .fill(color)
                    .frame(width: max(0, geo.size.width * ratio), height: 13)
                    // タイマー更新間隔（0.01秒）に合わせた短いアニメーション時間で
                    // 滑らかな減少に見せる（0.01秒より長くすると「ガクガク」感が出る）
                    .animation(.linear(duration: 0.01), value: ratio)
            }
        }
        .frame(height: 13)
    }
}

// MARK: - TileButton

/// 数字を表示するタップ可能なタイル。4枚がグリッドに並び、正解タイルをタップするとスコアが増える。
/// クイズの QuizChoiceButton と同じ視覚スタイルを踏襲する：
///   - 背景：薄い色（opacity 0.15）
///   - 枠線：DS.gaugeFull（正解）/ DS.gaugeWarn（不正解）のカラーボーダー
///   - アイコン：右上に checkmark / xmark
///   - スケール：正解時のみ 1.03 に拡大
/// タップ時の押し込みスケールは TileButtonStyle が担う（責任の分離）。
struct TileButton: View {
    let value:  Int
    /// 正解=緑 / 不正解=赤 / nil=通常。GameViewModelの tappedTileValue と answerMark から決まる
    var highlightState: AnswerMark? = nil
    let action: () -> Void

    /// state に応じた背景色。クイズと同じ opacity(0.15) の薄い色を使う。
    private var bgColor: Color {
        switch highlightState {
        case .correct: return DS.gaugeFull.opacity(0.15)
        case .wrong:   return DS.gaugeWarn.opacity(0.15)
        case nil:      return DS.choiceFill
        }
    }

    /// state に応じた枠線色。正解・不正解のみ色付き枠線を表示する。
    private var borderColor: Color {
        switch highlightState {
        case .correct: return DS.gaugeFull
        case .wrong:   return DS.gaugeWarn
        case nil:      return DS.muted.opacity(0.15)
        }
    }

    var body: some View {
        Button(action: action) {
            ZStack {
                // ── 背景 + 枠線 ──────────────────────────────
                RoundedRectangle(cornerRadius: DS.btnRadius)
                    .fill(bgColor)
                    .overlay(
                        RoundedRectangle(cornerRadius: DS.btnRadius)
                            .stroke(borderColor, lineWidth: 1.8)
                    )
                    // 回答前のみシャドウを表示してタップ可能感を演出する
                    .shadow(
                        color: .black.opacity(highlightState == nil ? 0.07 : 0),
                        radius: 6, x: 0, y: 3
                    )

                // ── 数字 ────────────────────────────────────
                Text("\(value)")
                    .font(.system(size: 40, weight: .bold, design: .rounded))
                    .foregroundStyle(DS.textPrimary)
                    .frame(maxWidth: .infinity)

                // ── 正解アイコン（右上） ──────────────────────
                if highlightState == .correct {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(DS.gaugeFull)
                        .font(.system(size: 18, weight: .bold))
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                        .padding(8)
                }

                // ── 不正解アイコン（右上） ────────────────────
                if highlightState == .wrong {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(DS.gaugeWarn)
                        .font(.system(size: 18, weight: .bold))
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                        .padding(8)
                }
            }
            .frame(height: 76)
        }
        .buttonStyle(TileButtonStyle())
        // 正解ボタンのみわずかに拡大して正解を視覚的に強調する（クイズと同じ 1.03）
        .scaleEffect(highlightState == .correct ? 1.03 : 1.0)  // ← 変更可
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: highlightState)
    }
}

// MARK: - TileButtonStyle

/// タイルボタン専用の ButtonStyle。押下中に1.07倍に拡大してタップ感を演出する。
/// ★ ButtonStyle として切り出す理由 ★
///   SwiftUI の Button は内部でタッチアニメーションを持っており、
///   .scaleEffect を直接書くとそれと干渉することがあります。
///   ButtonStyle の makeBody 内で scaleEffect を適用することで
///   干渉を避けつつ確実に押し込みアニメーションを実現できます。
struct TileButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            // configuration.isPressed: 指が触れている間だけ true になる
            .scaleEffect(configuration.isPressed ? 1.07 : 1.0)   // ← 変更可（押下時の拡大率）
            .animation(.easeInOut(duration: 0.11), value: configuration.isPressed)
    }
}

// MARK: - AnswerMarkView

/// 正解・不正解に対応する大きな絵文字マークを表示するView。
/// GameViewModel の answerMark がセットされたときに PlayingView の ZStack 上に重なって表示され、
/// 0.5秒後に nil に戻ることで自動的に消える（消す処理は GameViewModel 側の didSet で行う）。
struct AnswerMarkView: View {
    let mark: AnswerMark

    /// 正解は⭕️、不正解は❌。絵文字で直感的に結果を伝える。
    private var emoji: String { mark == .correct ? "⭕️" : "❌" }

    var body: some View {
        Text(emoji).font(.system(size: 100))
    }
}

// MARK: - ReactionView

/// コンボ達成時に右上から浮かび上がり、フェードアウトして消える絵文字リアクションView。
/// 表示・アニメーション・削除通知をすべてこのView内で完結させる自己完結型のコンポーネント。
///
/// ★ 自己完結型とは？ ★
///   親View（PlayingView）はこのViewを ForEach で並べるだけでよく、
///   「いつ動かすか」「いつ消すか」をこのView自身が管理します。
///   親がアニメーションの詳細を知る必要がないため、コードがシンプルになります。
struct ReactionView: View {
    let reaction:   Reaction
    /// アニメーション完了後に呼ばれるコールバック。
    /// 親（PlayingView）はこれを受けて reactions 配列から該当要素を削除する。
    let onFinished: () -> Void

    /// 上方向への移動量（ポイント）。onAppear でアニメーションが開始されると 0 → -travel に変化する。
    @State private var offsetY: CGFloat = 0
    @State private var opacity: Double  = 1.0

    private let duration: Double  = 2.0   // アニメーション全体の所要時間（秒）← 変更可
    private let travel:   CGFloat = 150   // 浮かび上がる縦移動距離（ポイント）← 変更可

    var body: some View {
        Text(reaction.emoji)
            .font(.system(size: 24))
            .offset(y: offsetY)   // 上方向にずれるアニメーション値
            .opacity(opacity)     // フェードアウトするアニメーション値
            // 右端を基準に、xOffset で各リアクションの横位置を少しずらして重なりを避ける
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
            .padding(.top, 140 + reaction.xOffset * 0.5)
            .padding(.trailing, 44)
            // タッチイベントをすり抜けさせてタイル操作を妨げない
            .allowsHitTesting(false)
            .onAppear {
                // ── 上方向への移動アニメーション ──────────────
                // duration 秒かけて 150pt 浮き上がる（easeOut = 最初は速く、徐々に遅くなる）
                withAnimation(.easeOut(duration: duration)) {
                    offsetY = -travel
                }

                // ── フェードアウト（60%経過後から開始）────────
                // 最初の 60% は不透明なまま浮き上がり、残り 40% でゆっくり消える。
                // 最初から消え始めると存在感が薄くなるため、あえて遅らせている。
                DispatchQueue.main.asyncAfter(deadline: .now() + duration * 0.6) {
                    withAnimation(.easeIn(duration: duration * 0.4)) {
                        opacity = 0.0
                    }
                }

                // ── 削除通知（アニメーション完了後）────────────
                // duration + 0.1 秒（少し余裕を持たせる）後に親へ削除を依頼する。
                // reactions 配列から削除されると SwiftUI がこの View を画面から取り除く。
                DispatchQueue.main.asyncAfter(deadline: .now() + duration + 0.1) {
                    onFinished()
                }
            }
    }
}
