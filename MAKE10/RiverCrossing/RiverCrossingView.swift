//
//  RiverCrossingView.swift
//  FDL-TenBlitz
//
//  Created by 空飛ぶ研究室(FlyingDevLab) on 2026/11/03.
//

// 川わたりパズルの画面。
//
// ★ このファイルの構成 ★
//   RiverCrossingView … ルートView（上から ステージ選択・決まりごと（回数もここ）・川・ボタン）
//   ─ 部品（private）─────────────────────────
//   StageBar          … 4つのステージのボタン
//   RulesCard         … そのステージの正式な名前と決まりごと、最短の回数と自分の記録
//   RiverScene        … むこう岸・川と舟・こちら岸
//   ActorToken        … 駒1つ（タップで舟に乗る・降りる）
//   ClearCard         … わたりきったときに川の上に重ねる表示
//
// ★ 岸を上下に積んでいる理由 ★
//   Web 版は広い画面だけ左右に並べるが、iPhone の幅で左右に並べると、
//   8にんの いかだ（駒が8つ）で片側の岸が100pt ほどになり、駒が2列しか入らない。
//   上下に積めば岸が画面いっぱいの幅になり、駒が5つ並ぶ。
//   そのため縦で遊ぶゲームにしている（MakeTenContentView の isPortraitOnlyScreen）。
//
// ★ 岸の呼び方を「左・右」「上・下」にしていない ★
//   「こちらぎし」「むこうぎし」なら、並べ方を変えても意味が合う。
//
// ★ 縦の長さを詰めている理由 ★
//   8にんの いかだ では、岸の駒が2段になり、決まりごとも4行ある。
//   わたる を押すたびにスクロールしなければならないと遊びにくいので、
//   iPhone の画面に ボタンまで収まるよう、駒の大きさや余白を決めている。
//   一言（「おおかみが やぎを ねらってる！」など）を川の上に重ねて出しているのも、
//   そのための行を別に取らずに済ませるため（RiverScene の messageToast を参照）。

import SwiftUI

// MARK: - 配色（この画面だけのもの）

private enum RiverColors {
    static let grass     = Color(red: 0.66, green: 0.85, blue: 0.47)
    static let grass2    = Color(red: 0.55, green: 0.77, blue: 0.34)
    static let grassInk  = Color(red: 0.24, green: 0.42, blue: 0.11)   // 岸の名前
    static let water     = Color(red: 0.25, green: 0.58, blue: 0.78)
    static let water2    = Color(red: 0.17, green: 0.48, blue: 0.67)
    static let wood      = Color(red: 0.75, green: 0.54, blue: 0.31)
    static let wood2     = Color(red: 0.61, green: 0.42, blue: 0.21)
    static let warn      = Color(red: 0.75, green: 0.26, blue: 0.17)   // 危ないことが起きかけたとき
}

// MARK: - RiverCrossingView（ルート）

struct RiverCrossingView: View {

    @State private var viewModel = RiverCrossingViewModel()
    /// 駒が岸と舟の間を移るときに、跳んで見えるようにするための名前空間
    @Namespace private var tokenSpace

    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                StageBar(viewModel: viewModel)

                RulesCard(viewModel: viewModel)

                RiverScene(viewModel: viewModel, tokenSpace: tokenSpace)
                    // クリアしたら盤は触れない。下に見えている川は、重ねたカードの背景として残す
                    .allowsHitTesting(!viewModel.isCleared)
                    // ★ ZStack ではなく overlay で重ねている理由 ★
                    //   ScrollView の中の ZStack に if で足したところ、クリアしても
                    //   カードが描かれないことがあった（盤は触れなくなっていた）。overlay なら確実に出る。
                    .overlay {
                        if viewModel.isCleared {
                            ClearCard(viewModel: viewModel)
                                .transition(.opacity)
                        }
                    }

                controls
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
        .scrollBounceBehavior(.basedOnSize)
        .onAppear(perform: playScreenshotScene)
    }

    // MARK: ボタン

    /// 川の下にまとめている。川の上や横に置くと、駒を触っている指がそのままボタンに届いてしまう。
    private var controls: some View {
        HStack(spacing: 8) {
            // わたる は、漕げる人が乗っていなくても押せる。押すと理由が出る
            // （8にんの いかだで「こげるのは3人だけ」を押して覚えてもらうため）
            RiverButton(label: "river_cross", icon: "arrow.up.arrow.down", isPrimary: true,
                        disabled: !viewModel.canCross) { viewModel.cross() }
            RiverButton(label: "river_undo", icon: "arrow.uturn.backward", isPrimary: false,
                        disabled: !viewModel.canUndo) { viewModel.undo() }
            RiverButton(label: "river_reset", icon: "arrow.counterclockwise", isPrimary: false,
                        disabled: false) { viewModel.restart() }
        }
    }

    // MARK: 撮影モード

    /// 撮影モード（ScreenshotMode.swift を参照）: おおかみと やぎと キャベツで、せんどうと やぎを舟に乗せておく。
    private func playScreenshotScene() {
        guard ScreenshotMode.scene == .river else { return }
        viewModel.select(.wolf)
        viewModel.restart()
        let actors = RiverStage.wolf.actors
        ScreenshotMode.after(0.8) { viewModel.tap(actors[0]) }   // せんどう
        ScreenshotMode.after(1.2) { viewModel.tap(actors[2]) }   // やぎ
    }
}

// MARK: - ステージ選択

/// 4つとも最初から選べる。遊んでいる途中でも切り替えられるが、切り替えると盤は最初からになる。
/// ボタンには短い名前だけを出す（正式な名前は下の RulesCard の見出しに出る）。
private struct StageBar: View {
    var viewModel: RiverCrossingViewModel

    var body: some View {
        HStack(spacing: 6) {
            ForEach(Array(RiverStage.allCases.enumerated()), id: \.element) { index, stage in
                let isOn = stage == viewModel.stage
                Button {
                    SoundManager.shared.playTap()
                    withAnimation(.easeInOut(duration: 0.25)) { viewModel.select(stage) }
                } label: {
                    VStack(spacing: 2) {
                        ActorFace(actor: stage.iconActor, size: 24, emojiSize: 18)
                        Text(stage.shortTitle)
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundStyle(isOn ? DS.primary : DS.textPrimary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 11)
                    .padding(.bottom, 4)
                    .padding(.horizontal, 2)
                    .background(
                        RoundedRectangle(cornerRadius: DS.tagRadius)
                            // 選んでいるステージはうすい青（不透明にして、かべがみの上でも灰色に濁らないようにする）
                            .fill(isOn ? Color(red: 0.93, green: 0.96, blue: 0.99) : DS.card)
                            .overlay(
                                RoundedRectangle(cornerRadius: DS.tagRadius)
                                    .stroke(isOn ? DS.primary : Color.clear, lineWidth: 2)
                            )
                            .shadow(color: .black.opacity(0.06), radius: 4, y: 2)
                    )
                    // 番号の丸。上に抜いた余白の左肩に置く
                    .overlay(alignment: .topLeading) {
                        Text(verbatim: "\(index + 1)")
                            .font(.system(size: 10, weight: .black, design: .rounded))
                            .foregroundStyle(.white)
                            .frame(width: 16, height: 16)
                            .background(Circle().fill(isOn ? DS.primary : DS.muted))
                            .padding(5)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(stage.title))
                .accessibilityAddTraits(isOn ? .isSelected : [])
            }
        }
    }
}

// MARK: - 決まりごと

/// 見出しがステージの正式な名前。その下に、そのステージだけの決まり。
/// 最後の1行は最短の回数・自分の記録と、いま渡った回数で、上に点線を引いて「これはルールではない」ことを見せる。
private struct RulesCard: View {
    var viewModel: RiverCrossingViewModel

    var body: some View {
        let stage = viewModel.stage
        VStack(alignment: .leading, spacing: 5) {
            Text(stage.title)
                .font(.system(size: 15, weight: .black, design: .rounded))
                .foregroundStyle(DS.textPrimary)

            VStack(alignment: .leading, spacing: 2) {
                ForEach(stage.rules.indices, id: \.self) { i in
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Circle()
                            .fill(RiverColors.water.opacity(0.6))
                            .frame(width: 5, height: 5)
                            .alignmentGuide(.firstTextBaseline) { $0[.bottom] - 1 }
                        Text(stage.rules[i])
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .font(.system(size: 12, weight: .medium, design: .rounded))
            .foregroundStyle(DS.muted)

            Line()
                .stroke(style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                .foregroundStyle(DS.muted.opacity(0.35))
                .frame(height: 1)

            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("river_par \(stage.par)")
                    if let best = viewModel.best(for: stage) {
                        Text("river_your_best \(best)")
                    }
                }
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(DS.muted)

                Spacer()

                // 渡った回数。時間は出さない（RiverCrossingViewModel 冒頭を参照）
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("river_crossings")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(DS.muted)
                    Text(verbatim: "\(viewModel.moves)")
                        .font(.system(size: 22, weight: .black, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(RiverColors.water2)
                        .contentTransition(.numericText())
                        .animation(.easeOut(duration: 0.2), value: viewModel.moves)
                }
                .accessibilityElement(children: .combine)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: DS.tagRadius).fill(DS.card)
            .shadow(color: .black.opacity(0.06), radius: 4, y: 2))
    }

    /// 横1本の線（点線を引くのに使う）
    private struct Line: Shape {
        func path(in rect: CGRect) -> Path {
            Path { p in
                p.move(to: CGPoint(x: rect.minX, y: rect.midY))
                p.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
            }
        }
    }
}

// MARK: - 川

/// むこう岸・川と舟・こちら岸。
/// 舟は frame の alignment を .top / .bottom で切り替えて動かしている（alignment の変化はアニメーションする）。
private struct RiverScene: View {
    var viewModel: RiverCrossingViewModel
    let tokenSpace: Namespace.ID

    /// 舟の絵があるか（無ければ木の箱の形で描く）
    private var boatArt: UIImage? { RiverArt.boat }

    var body: some View {
        VStack(spacing: 0) {
            bank(.far)
            river
            bank(.near)
        }
        .clipShape(RoundedRectangle(cornerRadius: DS.cardRadius))
        .shadow(color: .black.opacity(0.08), radius: 8, y: 4)
    }

    // MARK: 岸

    private func bank(_ side: RiverSide) -> some View {
        VStack(spacing: 4) {
            Text(side == .far ? "river_far_side" : "river_this_side")
                .font(.system(size: 10, weight: .black, design: .rounded))
                .foregroundStyle(RiverColors.grassInk)

            tokenRow(viewModel.actors(at: side), seats: 0)
                .frame(minHeight: ActorToken.height)
        }
        .padding(.horizontal, 8)
        .padding(.top, 5)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity)
        .background(
            // 草の明暗を上下で逆にして、2つの岸を見分けられるようにする
            LinearGradient(colors: [RiverColors.grass, RiverColors.grass2],
                           startPoint: side == .far ? .top : .bottom,
                           endPoint:   side == .far ? .bottom : .top)
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(side == .far ? "river_far_side" : "river_this_side"))
    }

    // MARK: 川と舟

    private var river: some View {
        ZStack {
            LinearGradient(colors: [RiverColors.water2, RiverColors.water, RiverColors.water2],
                           startPoint: .top, endPoint: .bottom)
            Waves()
                .stroke(.white.opacity(0.12), lineWidth: 4)

            boat
                .frame(maxHeight: .infinity,
                       alignment: viewModel.boatAt == .far ? .top : .bottom)
                .padding(.vertical, boatArt == nil ? 8 : 2)

            messageToast
                .frame(maxHeight: .infinity,
                       alignment: viewModel.boatAt == .far ? .bottom : .top)
                .padding(10)
        }
        // 絵の舟は札を乗せると高くなる（約102pt）ので、動いて見えるように川を広げる
        .frame(height: boatArt == nil ? 140 : 162)
    }

    @ViewBuilder
    private var boat: some View {
        let row = tokenRow(viewModel.actors(at: .boat), seats: viewModel.emptySeats)
        if let art = boatArt {
            // ★ 寸法は実物の船体に合わせてある ★
            //   絵の舟は 560 × 183。舟べりの内側の線は上から 65px のあたりなので、
            //   210pt 幅で描くと舟底から 44pt の高さに来る。札の下端をそこに合わせると、
            //   札が舟の中に座って見える（Web 版の style.css と同じ数字）。絵を差し替えたら、この2つの数も直す。
            row
                .padding(.horizontal, 14)
                .padding(.bottom, 44)
                .frame(width: 210)
                .background(alignment: .bottom) {
                    Image(uiImage: art)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 210)
                }
        } else {
            row
                .padding(.horizontal, 10)
                .padding(.top, 7)
                .padding(.bottom, 11)
                .background(
                    UnevenRoundedRectangle(topLeadingRadius: 10, bottomLeadingRadius: 26,
                                           bottomTrailingRadius: 26, topTrailingRadius: 10)
                        .fill(LinearGradient(colors: [RiverColors.wood, RiverColors.wood2],
                                             startPoint: .top, endPoint: .bottom))
                        .shadow(color: .black.opacity(0.25), radius: 5, y: 3)
                )
        }
    }

    // MARK: 一言

    /// 「おおかみが やぎを ねらってる！」「ふねは もう いっぱいだよ。」など。
    /// 舟のいない側の水の上に出す（舟が むこうぎし なら下、こちらぎし なら上）。
    /// ルール違反のときは舟が渡り切った先で起きかけたことを見せるので、舟とは重ならない。
    private var messageToast: some View {
        ZStack {
            if let message = viewModel.message {
                Text(message.text)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(RiverColors.warn)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(Capsule().fill(.white.opacity(0.95)))
                    .shadow(color: .black.opacity(0.15), radius: 4, y: 2)
                    .transition(.scale(scale: 0.94).combined(with: .opacity))
            }
        }
        .animation(.easeOut(duration: 0.2), value: viewModel.message)
    }

    // MARK: 駒の並び

    /// 駒を折り返して並べる。舟のときは空いている席も点線で出し、何人まで乗れるかを見ただけで分かるようにする。
    private func tokenRow(_ actors: [RiverActor], seats: Int) -> some View {
        FlowRow(spacing: 6) {
            ForEach(actors) { actor in
                ActorToken(actor: actor, enabled: viewModel.canTap(actor)) {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { viewModel.tap(actor) }
                }
                .matchedGeometryEffect(id: actor.id, in: tokenSpace)
                .accessibilityValue(Text(sideLabel(for: actor)))
            }
            ForEach(0..<seats, id: \.self) { _ in
                RoundedRectangle(cornerRadius: 13)
                    .strokeBorder(.white.opacity(0.5), style: StrokeStyle(lineWidth: 2, dash: [5, 4]))
                    .frame(width: ActorToken.width, height: boatArt == nil ? ActorToken.height : 26)
                    .frame(height: ActorToken.height, alignment: .bottom)
                    .accessibilityHidden(true)
            }
        }
    }

    private func sideLabel(for actor: RiverActor) -> LocalizedStringKey {
        switch viewModel.side(of: actor) {
        case .boat: return "river_in_boat"
        case .far:  return "river_far_side"
        case .near: return "river_this_side"
        }
    }

    /// 川の流れの筋（飾り）
    private struct Waves: Shape {
        func path(in rect: CGRect) -> Path {
            var p = Path()
            let step: CGFloat = 46
            var x: CGFloat = -rect.height
            while x < rect.maxX {
                p.move(to: CGPoint(x: x, y: rect.maxY))
                p.addLine(to: CGPoint(x: x + rect.height * 0.22, y: rect.minY))
                x += step
            }
            return p
        }
    }
}

// MARK: - 駒

/// 駒1つ。顔（絵か絵文字）と名前。役ごとに枠の色を変えている。
/// 色だけに意味を持たせていない（名前も顔も出ている）ので、色が見分けられなくても困らない。
private struct ActorToken: View {
    static let width:  CGFloat = 56
    static let height: CGFloat = 58

    let actor:   RiverActor
    let enabled: Bool
    let onTap:   () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 1) {
                ActorFace(actor: actor, size: 32, emojiSize: 22)
                Text(actor.name)
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(DS.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            .padding(.horizontal, 2)
            .frame(width: Self.width, height: Self.height)
            .background(
                RoundedRectangle(cornerRadius: 13)
                    .fill(tintBackground)
                    .overlay(RoundedRectangle(cornerRadius: 13).stroke(tint, lineWidth: 2))
                    .shadow(color: .black.opacity(0.12), radius: 2, y: 2)
            )
        }
        .buttonStyle(.plain)
        // 舟が着いていない岸の駒は押せない。押せないことを薄さで見せる
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.45)
    }

    /// 枠の色（Web 版の style.css と同じ値）
    private var tint: Color {
        switch actor.kind {
        case .person, .adult:               return Color(red: 0.30, green: 0.50, blue: 0.82)
        case .beast:                        return Color(red: 0.76, green: 0.45, blue: 0.18)
        case .thing:                        return Color(red: 0.37, green: 0.64, blue: 0.24)
        case .kid, .son, .daughter, .child: return Color(red: 0.83, green: 0.45, blue: 0.61)
        case .parent:                       return Color(red: 0.54, green: 0.42, blue: 0.78)
        case .dog:                          return Color(red: 0.73, green: 0.57, blue: 0.13)
        }
    }

    /// 札の地の色。枠の色をうすくしたもの（Web 版と同じ値。かべがみの上でも透けないよう不透明にしている）
    private var tintBackground: Color {
        switch actor.kind {
        case .person, .adult:               return Color(red: 0.93, green: 0.96, blue: 0.99)
        case .beast:                        return Color(red: 0.99, green: 0.95, blue: 0.89)
        case .thing:                        return Color(red: 0.94, green: 0.97, blue: 0.91)
        case .kid, .son, .daughter, .child: return Color(red: 0.99, green: 0.93, blue: 0.96)
        case .parent:                       return Color(red: 0.95, green: 0.93, blue: 0.98)
        case .dog:                          return Color(red: 0.98, green: 0.96, blue: 0.88)
        }
    }
}

/// 駒の顔。絵があれば絵、無ければ絵文字。読み上げには使わない（名前が読まれる）。
private struct ActorFace: View {
    let actor:     RiverActor
    let size:      CGFloat
    let emojiSize: CGFloat

    var body: some View {
        Group {
            if let image = RiverArt.image(actor.art) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
            } else {
                Text(verbatim: actor.emoji)
                    .font(.system(size: emojiSize))
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

// MARK: - ボタン

private struct RiverButton: View {
    let label:     LocalizedStringKey
    let icon:      String
    let isPrimary: Bool
    let disabled:  Bool
    let action:    () -> Void

    var body: some View {
        Button {
            SoundManager.shared.vibrate()
            action()
        } label: {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .bold))
                Text(label)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .foregroundStyle(isPrimary ? .white : DS.textPrimary)
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .background(
                RoundedRectangle(cornerRadius: DS.tagRadius)
                    .tintFill(isPrimary ? DS.primary : DS.card)
                    .overlay(RoundedRectangle(cornerRadius: DS.tagRadius)
                        .stroke(isPrimary ? DS.primary : DS.muted.opacity(0.2), lineWidth: 2))
            )
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.45 : 1)
    }
}

// MARK: - クリア

/// 全員わたりきったときに川の上に重ねる表示。
private struct ClearCard: View {
    var viewModel: RiverCrossingViewModel

    var body: some View {
        let stage = viewModel.stage
        let moves = viewModel.moves
        VStack(spacing: 8) {
            Text("river_everyone_across")
                .font(.system(size: 22, weight: .black, design: .rounded))
                .foregroundStyle(RiverColors.water2)
                .multilineTextAlignment(.center)

            Text("river_result \(moves)")
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(DS.textPrimary)

            Group {
                if viewModel.isNewBest {
                    Text("river_new_best")
                } else if let best = viewModel.previousBest {
                    Text("river_best_so_far \(best)")
                }
            }
            .font(.system(size: 14, weight: .bold, design: .rounded))
            .foregroundStyle(viewModel.isNewBest ? DS.gold : DS.accent)

            Group {
                if moves == stage.par {
                    Text("river_note_shortest")
                } else {
                    Text("river_note_par \(stage.par)")
                }
            }
            .font(.system(size: 12, weight: .medium, design: .rounded))
            .foregroundStyle(DS.muted)
            .multilineTextAlignment(.center)

            EnergyRewardBanner()

            HStack(spacing: 8) {
                RiverButton(label: "river_again", icon: "arrow.counterclockwise", isPrimary: true,
                            disabled: false) {
                    withAnimation(.easeInOut(duration: 0.25)) { viewModel.restart() }
                }
                if let next = viewModel.nextStage {
                    RiverButton(label: "river_next_stage", icon: "chevron.right", isPrimary: false,
                                disabled: false) {
                        withAnimation(.easeInOut(duration: 0.25)) { viewModel.select(next) }
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(RoundedRectangle(cornerRadius: DS.cardRadius).fill(.white.opacity(0.95)))
    }
}

// MARK: - 折り返して並べる

/// 子を左から並べ、入り切らなければ次の行へ折り返す（中央寄せ）。
/// 岸の駒（最大8つ）を、画面の幅に合わせて何列でも並べるために使う。
private struct FlowRow: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(subviews, width: proposal.width ?? .infinity)
        let width  = rows.map(\.width).max() ?? 0
        let height = rows.map(\.height).reduce(0, +) + spacing * CGFloat(max(0, rows.count - 1))
        return CGSize(width: proposal.width ?? width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(subviews, width: bounds.width) {
            var x = bounds.minX + (bounds.width - row.width) / 2
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y + (row.height - size.height) / 2),
                                      proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private struct Row { var indices: [Int] = []; var width: CGFloat = 0; var height: CGFloat = 0 }

    private func arrange(_ subviews: Subviews, width: CGFloat) -> [Row] {
        var rows: [Row] = []
        var row = Row()
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let needed = row.indices.isEmpty ? size.width : row.width + spacing + size.width
            if needed > width, !row.indices.isEmpty {
                rows.append(row)
                row = Row()
            }
            row.width  = row.indices.isEmpty ? size.width : row.width + spacing + size.width
            row.height = max(row.height, size.height)
            row.indices.append(index)
        }
        if !row.indices.isEmpty { rows.append(row) }
        return rows
    }
}
