//
//  PlayingView.swift
//  FDL-TenBlitz
//
//  Created by 空飛ぶ研究室(FlyingDevLab) on 2026/03/08.
//

// ゲームプレイ中の画面を構成するViewファイル。
// 問題カード・タイルグリッド・コンボリアクション・正誤マークを重ねて表示する。
// 各UIパーツはサブViewとして独立させ、PlayingViewはレイアウトのみを担う。

import SwiftUI

// MARK: - Playing View

struct PlayingView: View {
    var viewModel: GameViewModel

    // タイルを2列グリッドで並べる定義。列間隔はEmojiQuizHomeViewと統一している
    let columns = [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)]

    var body: some View {
        ZStack {
            VStack(spacing: 0) {

                // 問題カード：現在の問題番号・次の問題番号・タイムゲージを表示する
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

                // タイルグリッド（絵文字クイズと同じ幅・間隔）
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(0..<4, id: \.self) { index in
                        TileButton(value: viewModel.tiles[index]) {
                            withAnimation(.spring(response: 0.28, dampingFraction: 0.75)) {
                                viewModel.answer(viewModel.tiles[index])
                            }
                        }
                        // "tile-{index}-{value}"形式のIDでSwiftUIに新旧タイルを区別させ、
                        // 正解後に新しい数字が上からスライドインするトランジションを確実に発火させる
                        .id("tile-\(index)-\(viewModel.tiles[index])")
                        .transition(.asymmetric(
                            insertion: .scale(scale: 0.4).combined(with: .opacity),
                            removal:   .scale(scale: 0.4).combined(with: .opacity)
                        ))
                    }
                }
                .padding(.horizontal, 20)

                Spacer()
            }

            // コンボリアクション：コンボ達成時に右上から浮かび上がる絵文字。
            // 各ReactionViewはアニメーション完了後にonFinishedコールバックで自身をViewModelから削除する
            ForEach(viewModel.reactions) { r in
                ReactionView(reaction: r) { viewModel.removeReaction(id: r.id) }
            }

            // 正誤マーク（問題カードとタイルの隙間に表示）
            // allowsHitTesting(false)でタッチをすり抜けさせ、マーク表示中もタイルを操作できるようにする
            if let mark = viewModel.answerMark {
                AnswerMarkView(mark: mark)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .padding(.top, 122) // カード下端(192) - マーク半高(22) ≈ 隙間中央
                    .transition(.asymmetric(
                        insertion: .scale(scale: 0.5).combined(with: .opacity),  // 小→等倍でポップイン
                        removal:   .scale(scale: 1.3).combined(with: .opacity)   // 等倍→大でポップアウト
                    ))
                    .allowsHitTesting(false)
                    .zIndex(30)
            }
        }
        // answerMarkの変化をトリガーに正誤マークのトランジションをスプリングで動かす
        .animation(.spring(response: 0.25, dampingFraction: 0.6), value: viewModel.answerMark)
    }
}

// MARK: - Problem Card View

// 現在の問題番号・次の問題番号・タイムゲージを1枚のカードにまとめて表示するView。
// 高さを180ptに固定して、EmojiQuizHomeViewのQuizQuestionCardと高さを揃えている。
struct ProblemCardView: View {
    let questionNumber:     Int
    let nextQuestionNumber: Int
    let timeRemaining:      Double
    let maxTime:            Double
    let warnThreshold:      Double
    let gameMode:           GameMode

    // Blitzモードは赤系、通常モードは青系で問題番号とゲージを色分けする
    private var mainColor: Color { gameMode == .blitz ? DS.blitzColor : DS.primary }

    var body: some View {
        // 絵文字クイズのカードと同じ 180pt 固定
        VStack(spacing: 0) {
            Spacer(minLength: 0)

            // NEXT エリア：次の問題番号を薄く表示して予告する
            // nextQuestionNumberが変わるたびに上からスライドインするトランジションを適用する
            HStack(alignment: .lastTextBaseline, spacing: 6) {
                Text("playing_next_label")
                    .font(.system(size: 11, weight: .black, design: .rounded))
                    .foregroundStyle(mainColor.opacity(0.45))
                    .tracking(1.0)
                // .id(nextQuestionNumber)でSwiftUIに値の変化を伝え、トランジションを発火させる
                Text("\(nextQuestionNumber)")
                    .font(.system(size: 36, weight: .bold, design: .rounded))
                    .foregroundStyle(mainColor.opacity(0.32))
                    .id(nextQuestionNumber)
                    .transition(.asymmetric(
                        insertion: .move(edge: .top).combined(with: .opacity),
                        removal:   .move(edge: .bottom).combined(with: .opacity)
                    ))
                Spacer()
                // Blitzモードのときのみ右上にモードラベルを表示する
                if gameMode == .blitz {
                    Text("playing_blitz_mode_label")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(DS.blitzColor)
                }
            }
            .padding(.horizontal, 20)

            // メイン数字：現在の問題番号を大きく表示する
            // questionNumberが変わると上からスライドインして、古い数字は下にスライドアウトする
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

            // タイムゲージ：残り時間を横バーで表現する
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
        // .clipShape + .clipped()でカードの角丸からコンテンツがはみ出さないようにする
        .clipShape(RoundedRectangle(cornerRadius: DS.cardRadius))
        .clipped()
    }
}

// MARK: - Inline Gauge View

// 残り時間を横バーで表示するタイムゲージ。
// timeRemainingがwarnThreshold以下になると色が警告色（赤系）に切り替わる。
struct InlineGaugeView: View {
    let timeRemaining: Double
    let maxTime:       Double
    let warnThreshold: Double

    // 残り時間をmaxTimeに対する比率（0.0〜1.0）に変換してバーの幅に使う
    private var ratio: CGFloat { CGFloat(timeRemaining / maxTime) }
    // 残り時間が閾値以下になったら警告色（赤系）、それ以外は良好色（緑系）
    private var color: Color   { timeRemaining <= warnThreshold ? DS.gaugeWarn : DS.gaugeFull }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                // ゲージの背景トラック（薄いグレーの全幅バー）
                RoundedRectangle(cornerRadius: DS.gaugeRadius)
                    .fill(DS.gaugeBg)
                    .frame(height: 13)
                // 残り時間に比例した幅の前景バー。max(0, ...)で負の幅にならないよう保護する
                RoundedRectangle(cornerRadius: DS.gaugeRadius)
                    .fill(color)
                    .frame(width: max(0, geo.size.width * ratio), height: 13)
                    // タイマー更新間隔（0.01秒）に合わせて短いアニメーション時間を設定することで
                    // 滑らかな減少に見せる
                    .animation(.linear(duration: 0.01), value: ratio)
            }
        }
        .frame(height: 13)
    }
}

// MARK: - Tile Button

// 数字を表示するタップ可能なタイル。4枚がグリッドに並び、正解タイルをタップするとスコアが増える。
// タップ時のスケールアップはTileButtonStyleが担い、TileButton自身はコンテンツとレイアウトのみを持つ。
struct TileButton: View {
    let value:  Int
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text("\(value)")
                .font(.system(size: 40, weight: .bold, design: .rounded))
                .foregroundStyle(DS.textPrimary)
                .frame(maxWidth: .infinity)
                .frame(height: 76)
                .background(
                    RoundedRectangle(cornerRadius: DS.btnRadius)
                        .fill(DS.choiceFill)
                        .shadow(color: .black.opacity(0.07), radius: 6, x: 0, y: 3)
                )
        }
        .buttonStyle(TileButtonStyle())
    }
}

// タイルボタン専用のButtonStyle。押下中に1.07倍に拡大してタップ感を演出する。
// .buttonStyle()として切り出すことで、スケールエフェクトをコンテンツのアニメーションと
// 干渉させずに適用できる
struct TileButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 1.07 : 1.0)
            .animation(.easeInOut(duration: 0.11), value: configuration.isPressed)
    }
}

// MARK: - Answer Mark View

// 正解・不正解に対応する大きな絵文字マークを表示するView。
// GameViewModelのanswerMarkがセットされたときにPlayingViewのZStack上に重なって表示され、
// 0.5秒後にnilに戻ることで自動的に消える
struct AnswerMarkView: View {
    let mark: AnswerMark

    // 正解は⭕️、不正解は❌で直感的に伝える
    private var emoji: String { mark == .correct ? "⭕️" : "❌" }

    var body: some View {
        Text(emoji).font(.system(size: 100))
    }
}

// MARK: - Reaction View

// コンボ達成時に右上から浮かび上がり、フェードアウトして消える絵文字リアクションView。
// 表示・アニメーション・削除通知をすべてこのView内で完結させる自己完結型のコンポーネント。
struct ReactionView: View {
    let reaction:   Reaction

    // アニメーション完了後に呼ばれる。親（PlayingView）はこれを受けてreactions配列から削除する
    let onFinished: () -> Void

    // 上方向への移動量。onAppearでアニメーションが開始されると0 → -travelに変化する
    @State private var offsetY: CGFloat = 0
    @State private var opacity: Double  = 1.0

    private let duration: Double  = 2.0   // アニメーション全体の所要時間
    private let travel:   CGFloat = 150   // 浮かび上がる縦移動距離（ポイント）

    var body: some View {
        Text(reaction.emoji)
            .font(.system(size: 24))
            .offset(y: offsetY)
            .opacity(opacity)
            // 右端を基準に、xOffsetで各リアクションの横位置を少しずらして重なりを避ける
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
            .padding(.top, 140 + reaction.xOffset * 0.5)
            .padding(.trailing, 44)
            // タッチイベントをすり抜けさせて、リアクション表示中もタイル操作を妨げない
            .allowsHitTesting(false)
            .onAppear {
                // 上方向への移動アニメーション（duration秒かけて150pt浮き上がる）
                withAnimation(.easeOut(duration: duration)) {
                    offsetY = -travel
                }
                // 全体の60%が経過したタイミングからフェードアウト開始（残り40%で消える）
                DispatchQueue.main.asyncAfter(deadline: .now() + duration * 0.6) {
                    withAnimation(.easeIn(duration: duration * 0.4)) {
                        opacity = 0.0
                    }
                }
                // アニメーション完了後に少し余裕を持たせてから親に削除を通知する
                DispatchQueue.main.asyncAfter(deadline: .now() + duration + 0.1) {
                    onFinished()
                }
            }
    }
}
