//
//  MemoryGameView.swift
//  FDL-TenBlitz
//
//  Created by 空飛ぶ研究室(FlyingDevLab) on 2026/09/06.
//

// どうぶつめくり（神経衰弱）の画面本体。
// スタート画面 → 盤面 → 結果画面 の3段階を切り替える。
//
// ★ このファイルの構成 ★
//   MemoryGameView    … 3画面の切り替えとクリア演出の進行役
//   MemoryCardView    … カード1枚。3D回転でめくる
//   MemoryRewardPopup … そろえたときに浮かぶ「+◯kcal」（連続ならコンボ数も）
//
// ★ 役割分担 ★
//   進行の判断（めくってよいか・揃ったか・クリアか）は MemoryGameEngine が持ちます。
//   このファイルは「エンジンの状態を絵にする」ことと「タップを渡す」ことだけを行い、
//   ゲームのルールは一切持ちません。
//
// ★ クリア時の流れ ★
//   1. 最後のペアが揃うと engine.phase が .cleared になる
//   2. 薄くなっていた一致済みカードを元の濃さに戻す
//   3. 紙吹雪を出し、「おめでとう」を盤面に重ねる
//   4. clearBoardHold のあいだ揃った盤面を見せる
//   5. 結果画面（今回もらったエネルギー）へ移る
//   紙吹雪はこのViewのZStackに置いてあるため、画面が切り替わっても降り続けます。

import SwiftUI

// MARK: - MemoryGameView

struct MemoryGameView: View {

    // MARK: 画面

    /// このゲーム内での画面。MakeTenContentView の Screen とは別物（こちらはゲームの内側）。
    private enum Stage {
        case start    // 遊び方の説明
        case playing  // 盤面
        case result   // 結果（今回もらったエネルギー）
    }

    // MARK: 状態

    @State private var stage: Stage = .start

    // ★ @State に @Observable のクラスを置く理由 ★
    //   MemoryGameEngine は class（参照型）なので、View が作り直されても
    //   同じインスタンスが保たれます。@Observable と組み合わせることで、
    //   中身が変わったときだけ画面が更新されます。
    @State private var engine = MemoryGameEngine()

    /// 紙吹雪の表示。クリアで true にし、「もういちど」で false に戻す。
    @State private var showConfetti = false

    /// 「おめでとう」の表示。盤面を見せているあいだだけ true。
    @State private var showCongrats = false

    /// 一致済みカードの濃さを元に戻したか。クリア演出で true になる。
    @State private var restoreOpacity = false

    /// いま浮かべている「+◯kcal」。そろえるたびに増え、演出が終わると自分で消える。
    @State private var rewardPopups: [MemoryReward] = []

    // MARK: テーマ色

    // タイトル画面のタイル色と揃えている。カード裏面と「おめでとう」に使う。
    private let themeColor = Color.brown   // ← 変更可（タイル色と揃えること）

    // MARK: body

    var body: some View {
        ZStack {
            switch stage {
            case .start:
                startContent
                    .transition(.opacity)

            case .playing:
                boardContent
                    .transition(.opacity)

            case .result:
                MemoryResultView(onPlayAgain: playAgain)
                    .transition(.opacity)
            }

            // ★ zIndex について ★
            //   アプリ全体の階層は SharedFrame.swift の表に従う。
            //   40 は「おめでとう」用、45 は「+◯kcal」用に新しく取った値、50 は既存の紙吹雪の値。
            ForEach(rewardPopups) { reward in
                MemoryRewardPopup(reward: reward) {
                    rewardPopups.removeAll { $0.id == reward.id }
                }
                .zIndex(45)
            }

            if showCongrats {
                congratsOverlay
                    .zIndex(40)
            }

            // allowsHitTesting(false) でタップを下のViewへ素通しさせる
            if showConfetti {
                ConfettiView(isSpecial: false)
                    .allowsHitTesting(false)
                    .zIndex(50)
            }
        }
        // 全ペアが揃った瞬間を捉えてクリア演出を始める
        .onChange(of: engine.phase) { _, newPhase in
            guard newPhase == .cleared else { return }
            runClearSequence()
        }
        // そろえるたびに「+◯kcal」を浮かべる（エネルギーはエンジン側で加算済み）
        .onChange(of: engine.lastReward) { _, reward in
            guard let reward else { return }
            rewardPopups.append(reward)
        }
    }

    // MARK: - スタート画面

    // 他ゲームのスタート画面と同じ構成（遊び方カード + スタートボタン）。
    // このゲームはスコアを持たないため、ハイスコア欄は置かない。
    private var startContent: some View {
        VStack(spacing: 20) {
            Spacer()

            VStack(alignment: .leading, spacing: 12) {
                Label("How to Play", systemImage: "questionmark.circle.fill")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(DS.muted)

                howToRow(emoji: "👆", textKey: "memory_howto_flip")
                howToRow(emoji: "🐘", textKey: "memory_howto_match")
                howToRow(emoji: "🔥", textKey: "memory_howto_energy")
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(DS.card, in: RoundedRectangle(cornerRadius: DS.sectionRadius))
            .padding(.horizontal, 24)

            Spacer()

            Button {
                SoundManager.shared.vibrate()
                SoundManager.shared.playTap()
                engine.start()
                withAnimation(.easeInOut(duration: 0.3)) { stage = .playing }
            } label: {
                Text("ゲームスタート")
                    .font(.system(size: 26, weight: .black, design: .rounded))  // ← 変更可（ボタン文字サイズ）
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)                                      // ← 変更可（ボタン縦パディング）
                    .background(
                        RoundedRectangle(cornerRadius: DS.btnRadius)
                            .fill(themeColor)
                            .shadow(color: themeColor.opacity(0.35), radius: 8, x: 0, y: 4)
                    )
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
    }

    /// 遊び方カードの1行（絵文字 + 説明文）。絵文字は装飾なので翻訳対象に含めない。
    private func howToRow(emoji: String, textKey: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(emoji)
                .font(.system(size: 18))
            Text(textKey)
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .foregroundStyle(DS.textBody)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - 盤面

    // ★ カードの1辺をどう決めているか ★
    //   横基準（幅から余白と隙間を引いて列数で割る）と
    //   縦基準（高さから隙間を引いて行数で割る）の小さい方を採用します。
    //   こうすることで、画面の狭い端末でも縦にはみ出さず、スクロールも要りません。
    //   一覧できることが神経衰弱の本質なので、スクロールはさせません。
    private var boardContent: some View {
        GeometryReader { geo in
            let columns = MemoryTuning.columns
            let rows    = Int(ceil(Double(MemoryTuning.pairCount * 2) / Double(columns)))
            let spacing = MemoryTuning.cardSpacing

            let widthBased  = (geo.size.width
                               - MemoryTuning.boardPadding * 2
                               - spacing * CGFloat(columns - 1)) / CGFloat(columns)
            let heightBased = (geo.size.height
                               - spacing * CGFloat(rows - 1)) / CGFloat(rows)
            let side = max(1, min(widthBased, heightBased))

            LazyVGrid(
                columns: Array(
                    repeating: GridItem(.fixed(side), spacing: spacing),
                    count: columns
                ),
                spacing: spacing
            ) {
                // ForEach に CardState をそのまま渡せるのは Identifiable だから。
                // id で対応づけられるため、並びが変わってもアニメーションが崩れない。
                ForEach(engine.cards) { card in
                    MemoryCardView(
                        card:           card,
                        face:           engine.face(for: card),
                        label:          engine.accessibilityLabel(for: card),
                        side:           side,
                        backColor:      themeColor,
                        restoreOpacity: restoreOpacity
                    ) {
                        engine.tap(card.id)
                    }
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        // 通常の流れではスタートボタンで盤面が作られている。
        // 何らかの理由で未生成のまま入ってきた場合の安全網として呼ぶ（生成済みなら何もしない）。
        .onAppear { engine.startIfNeeded() }
    }

    // MARK: - クリア演出

    /// 「おめでとう」の帯。盤面の上に重ねる。
    private var congratsOverlay: some View {
        Text("memory_clear_congrats")
            .font(.system(size: 34, weight: .black, design: .rounded))  // ← 変更可（文字サイズ）
            .foregroundStyle(.white)
            .padding(.horizontal, 28)
            .padding(.vertical, 16)
            .background(
                Capsule()
                    .fill(themeColor)
                    .shadow(color: .black.opacity(0.18), radius: 10, x: 0, y: 4)
            )
            .transition(.scale.combined(with: .opacity))
            .allowsHitTesting(false)
    }

    /// クリアしたときの演出をまとめて進める。
    private func runClearSequence() {
        // 薄くなっていた一致済みカードを元の濃さに戻し、同時に「おめでとう」を出す。
        withAnimation(.easeOut(duration: MemoryTuning.clearRestore)) {
            restoreOpacity = true
            showCongrats   = true
        }
        showConfetti = true

        // 揃った盤面をしばらく見せてから、結果画面へ移す。
        DispatchQueue.main.asyncAfter(deadline: .now() + MemoryTuning.clearBoardHold) {
            withAnimation(.easeInOut(duration: 0.3)) {
                showCongrats = false
                stage        = .result
            }
        }
    }

    /// 「もういちど」で呼ばれる。演出の状態を戻してから盤面を作り直す。
    private func playAgain() {
        showConfetti   = false
        showCongrats   = false
        restoreOpacity = false
        rewardPopups   = []
        engine.start()
        withAnimation(.easeInOut(duration: 0.3)) { stage = .playing }
    }
}

// MARK: - MemoryRewardPopup

/// そろえたときに盤面の上へ浮かんで消える「+◯kcal」。2連続以上なら「◯れんぞく！」も添える。
/// 表示・移動・削除の依頼までを自分で行う自己完結型（PlayingView の ReactionView と同じ作り）。
private struct MemoryRewardPopup: View {
    let reward:     MemoryReward
    let onFinished: () -> Void

    @State private var offsetY: CGFloat = 0
    @State private var opacity: Double  = 0
    @State private var scale:   CGFloat = 0.6

    private let duration: Double  = 1.1   // ← 変更可（浮かんで消えるまでの秒数）
    private let travel:   CGFloat = 70    // ← 変更可（浮かぶ距離）

    var body: some View {
        VStack(spacing: 2) {
            if reward.combo >= 2 {
                Text("memory_combo_label \(reward.combo)")
                    .font(.system(size: 18, weight: .black, design: .rounded))
            }
            // 単位の kcal は全言語共通なので、ローカライズせずそのまま出す
            Text(verbatim: "+\(EnergyStore.format(reward.kcal))kcal")
                .font(.system(size: reward.combo >= 2 ? 30 : 22, weight: .black, design: .rounded))
        }
        .foregroundStyle(DS.energy)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(
            Capsule()
                .fill(DS.card)
                .shadow(color: DS.energy.opacity(0.25), radius: 6, x: 0, y: 3)
        )
        .scaleEffect(scale)
        .offset(y: offsetY)
        .opacity(opacity)
        .allowsHitTesting(false)   // 連打の邪魔をしないよう、タップは下のカードへ素通しさせる
        .onAppear {
            withAnimation(.spring(response: 0.25, dampingFraction: 0.55)) {
                scale   = 1
                opacity = 1
            }
            withAnimation(.easeOut(duration: duration)) {
                offsetY = -travel
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + duration * 0.6) {
                withAnimation(.easeIn(duration: duration * 0.4)) { opacity = 0 }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + duration + 0.1) {
                onFinished()
            }
        }
    }
}

// MARK: - MemoryCardView

// ★ 3D回転で「めくる」を表現する ★
//   rotation3DEffect の axis に (x:0, y:1, z:0) を指定すると、
//   縦の線を軸にしてカードが回ります。左右の辺が手前と奥に振れる、
//   トランプをめくるときの自然な動きになります。
//
// ★ 表面が鏡像になる問題 ★
//   カード全体を180度回すと、表面に置いた絵文字も一緒に裏返って鏡像になります。
//   これを打ち消すため、表面だけにあらかじめ180度の回転をかけてあります
//   （180 + 180 = 360 で元に戻る）。神経衰弱を作るとき必ず踏む定番のつまずきです。
//
// ★ 表と裏の入れ替わり ★
//   回転の途中（90度付近）でカードは真横を向き、幅がほぼゼロになります。
//   表裏の透明度を同じ長さで入れ替えると、その見えない瞬間に切り替わるため、
//   両面が同時に見えることはありません。

/// カード1枚。裏はテーマ色のベタ塗り、表は白地に絵文字。
private struct MemoryCardView: View {

    let card:           CardState
    let face:           CardFace
    let label:          LocalizedStringKey
    let side:           CGFloat
    let backColor:      Color
    /// クリア演出で薄さを解除するフラグ。true のあいだは一致済みでも濃いまま表示する。
    let restoreOpacity: Bool
    let onTap:          () -> Void

    /// 表を向けているか。確定済みのカードは表のまま残る。
    private var isFaceUp: Bool { card.isFaceUp || card.isMatched }

    /// 薄く表示するか。一致済みを薄くして、残っている裏向きのカードを目立たせる。
    private var isDimmed: Bool { card.isMatched && !restoreOpacity }

    var body: some View {
        ZStack {
            // ── 裏面 ──
            RoundedRectangle(cornerRadius: MemoryTuning.cardCornerRadius)
                .fill(backColor)
                .opacity(isFaceUp ? 0 : 1)

            // ── 表面 ──
            RoundedRectangle(cornerRadius: MemoryTuning.cardCornerRadius)
                .fill(DS.card)
                .overlay(faceContent)
                .opacity(isFaceUp ? 1 : 0)
                .rotation3DEffect(.degrees(180), axis: (x: 0, y: 1, z: 0))  // 鏡像の打ち消し
        }
        .frame(width: side, height: side)
        .shadow(color: .black.opacity(0.08), radius: 4, x: 0, y: 2)
        .rotation3DEffect(.degrees(isFaceUp ? 180 : 0), axis: (x: 0, y: 1, z: 0))
        .opacity(isDimmed ? MemoryTuning.matchedOpacity : 1)
        .animation(.easeInOut(duration: MemoryTuning.flipDuration), value: isFaceUp)
        .animation(.easeOut(duration: MemoryTuning.clearRestore), value: isDimmed)
        .contentShape(Rectangle())   // 角丸の外側もタップ判定に含めて、押しやすくする
        .onTapGesture(perform: onTap)
        .accessibilityElement()
        .accessibilityLabel(Text(label))
        .accessibilityAddTraits(.isButton)
    }

    // ★ switch で分岐する理由 ★
    //   CardFace に新しい種類が増えたとき、ここに分岐を足し忘れると
    //   コンパイルエラーになります。対応漏れが構造的に起きません。
    @ViewBuilder
    private var faceContent: some View {
        switch face {
        case .emoji(let emoji):
            Text(emoji)
                .font(.system(size: side * 0.55))   // ← 変更可（カード辺長に対する絵文字の比率）

        case .image(let image):
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .clipShape(RoundedRectangle(cornerRadius: MemoryTuning.cardCornerRadius))
        }
    }
}
