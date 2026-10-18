//
//  MemoryGameView.swift
//  FDL-TenBlitz
//
//  Created by 空飛ぶ研究室(FlyingDevLab) on 2026/09/06.
//

// どうぶつめくり（神経衰弱）の画面本体。
// スタート画面（カードの種類をえらぶ） → 盤面 → 結果画面 の3段階を切り替える。
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
        case start    // 遊び方の説明と、カードの種類えらび
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

    /// 前回あそんだカードの種類。スタート画面で、そのボタンに枠を付けて目印にする。
    @State private var selectedDeck: MemoryDeck = .lastPlayed

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
                MemoryResultView(deck: engine.deck, onPlayAgain: playAgain, onChangeDeck: backToStart)
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
        .onAppear { playScreenshotScene() }
    }

    /// 撮影モード（ScreenshotMode.swift を参照）: 5×5（まん中にロゴ）を始め、4組そろえてから1枚だけめくっておく。
    private func playScreenshotScene() {
        guard ScreenshotMode.scene == .memory else { return }
        startGame(.animals12)
        let pairs = Dictionary(grouping: engine.cards, by: \.pairID).values.map { $0 }
        for (i, pair) in pairs.prefix(4).enumerated() where pair.count == 2 {
            ScreenshotMode.after(1.0 + Double(i) * 1.2) {
                engine.tap(pair[0].id)
                engine.tap(pair[1].id)
            }
        }
        if pairs.count > 4, let single = pairs[4].first {
            ScreenshotMode.after(1.0 + 4 * 1.2) { engine.tap(single.id) }
        }
    }

    // MARK: - スタート画面

    // 遊び方カードと、カードの種類のボタン。このゲームはスコアを持たないため、ハイスコア欄は置かない。
    //
    // ★ スタートボタンを置かない理由 ★
    //   種類のボタンを押したら、すぐにゲームが始まる（えらぶ → スタート の2回押しにしない）。
    //   小さい子でも1回押すだけで遊び始められるようにするため。
    //
    // ★ ViewThatFits で3つの並べ方を用意している理由 ★
    //   上から順に「収まるもの」が選ばれる。
    //   ① 縦に並べる（iPhone の縦・iPad）
    //   ② 左に遊び方、右に種類のボタン（iPhone の横。高さが足りないとき）
    //   ③ どちらも収まらないときは、①をスクロールできるようにする
    private var startContent: some View {
        ViewThatFits(in: .vertical) {
            VStack(spacing: 24) {
                Spacer(minLength: 0)
                howToCard
                deckPicker
                Spacer(minLength: 0)
            }
            .padding(.vertical, 16)

            HStack(alignment: .center, spacing: 0) {
                howToCard
                    .frame(maxWidth: .infinity)
                deckPicker
                    .frame(maxWidth: .infinity)
            }
            .padding(.vertical, 12)

            ScrollView {
                VStack(spacing: 20) {
                    howToCard
                    deckPicker
                }
                .padding(.vertical, 16)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
    }

    /// 遊び方カード。
    private var howToCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("How to Play", systemImage: "questionmark.circle.fill")
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundStyle(DS.muted)

            howToRow(emoji: "👆", textKey: "memory_howto_flip")
            howToRow(emoji: "🐘", textKey: "memory_howto_match")
            howToRow(emoji: "🔥", textKey: "memory_howto_energy")
            howToRow(emoji: "🎁", textKey: "memory_howto_sticker")
        }
        .padding(16)
        .frame(maxWidth: 520, alignment: .leading)   // ← 変更可（iPad で横に広がりすぎないように）
        .background(DS.card, in: RoundedRectangle(cornerRadius: DS.sectionRadius))
        .padding(.horizontal, 24)
    }

    /// カードの種類をえらぶボタンの並び。幅に合わせて1行に入る数が変わる（iPhone は 3つ + 2つ、iPad は5つ）。
    private var deckPicker: some View {
        VStack(spacing: 10) {
            Text("memory_deck_choose")
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(DS.textPrimary)
                .wallpaperCushion()   // かべがみの上でも読めるように（DesignSystem.swift を参照）

            // ★ 「6つ1行」か「3つずつ2行」のどちらかにする理由 ★
            //   幅に合わせて自由に折り返すと、5つ + 1つ のように1つだけ取り残される行ができる。
            //   ViewThatFits で、6つが1行に入るならそうし、入らなければ 3列×2行 にする。
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) {
                    ForEach(MemoryDeck.allCases) { deck in
                        deckButton(deck)
                            .frame(width: 104)   // ← 変更可（1行に並べるときのボタンの幅）
                    }
                }
                LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 3),
                    spacing: 12
                ) {
                    ForEach(MemoryDeck.allCases) { deck in
                        deckButton(deck)
                    }
                }
            }
        }
        .frame(maxWidth: 720)   // ← 変更可（iPad で横に広がりすぎないように）
        .padding(.horizontal, 24)
    }

    /// カードの種類のボタン1つ。見本のカード・名前・盤面の大きさ・むずかしさ ボーナス を出す。
    /// 押すと、すぐにその種類でゲームが始まる。前回あそんだ種類には枠が付く。
    private func deckButton(_ deck: MemoryDeck) -> some View {
        let isSelected = deck == selectedDeck
        return Button {
            startGame(deck)
        } label: {
            VStack(spacing: 3) {
                Text(verbatim: deck.preview)
                    .font(.system(size: 32, weight: .heavy, design: .rounded))   // ← 変更可（見本の大きさ）
                    .foregroundStyle(DS.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .frame(height: 42)
                Text(deck.nameKey)
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(DS.textBody)
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
                    .multilineTextAlignment(.center)
                HStack(spacing: 4) {
                    Text(verbatim: deck.gridLabel)
                        .foregroundStyle(DS.muted)
                    if deck.isHard {
                        // むずかしい種類には、もらえるボーナスを先に見せて、挑戦したくなるようにする
                        Text(verbatim: "🔥+\(EnergyStore.format(MemoryTuning.hardClearBonus))")
                            .foregroundStyle(DS.energy)
                    }
                }
                .font(.system(size: 11, weight: .heavy, design: .rounded))
                .monospacedDigit()
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)   // ← 変更可（押すとすぐ始まる大事なボタンなので、押しやすく大きめに）
            .padding(.horizontal, 4)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(DS.card)
                    .shadow(color: .black.opacity(0.06), radius: 3, x: 0, y: 2)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(themeColor, lineWidth: isSelected ? 3 : 0)
            )
            .scaleEffect(isSelected ? 1.04 : 1)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    /// えらんだ種類で盤面を作ってゲームを始め、次のためにその種類を覚えておく。
    private func startGame(_ deck: MemoryDeck) {
        SoundManager.shared.vibrate()
        SoundManager.shared.playTap()
        selectedDeck          = deck
        MemoryDeck.lastPlayed = deck
        engine.start(deck: deck)
        withAnimation(.easeInOut(duration: 0.3)) { stage = .playing }
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
            let rows    = engine.deck.rows
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
                // ForEach に BoardCell をそのまま渡せるのは Identifiable だから。
                // id で対応づけられるため、並びが変わってもアニメーションが崩れない。
                ForEach(boardCells) { cell in
                    switch cell {
                    case .card(let card):
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
                    case .logo:
                        MemoryLogoCell(side: side)
                    }
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        // 通常の流れではスタートボタンで盤面が作られている。
        // 何らかの理由で未生成のまま入ってきた場合の安全網として呼ぶ（生成済みなら何もしない）。
        .onAppear { engine.startIfNeeded() }
    }

    /// 盤面の1マス。カードか、まん中のロゴ。
    private enum BoardCell: Identifiable {
        case card(CardState)
        case logo

        var id: String {
            switch self {
            case .card(let card): return card.id.uuidString
            case .logo:           return "logo"
            }
        }
    }

    // ★ ロゴをエンジンのカードに混ぜない理由 ★
    //   ロゴはめくれない飾りなので、ゲームのルール（エンジン）には関係ありません。
    //   エンジンはカード24枚だけを持ち、画面に並べるときにまん中へロゴを差し込みます。
    //   25マスのまん中は、0 から数えて 12番目（25 ÷ 2 の切り捨て）。

    /// 画面に並べるマスの一覧。5×5 の種類では、カードの並びのまん中にロゴを入れる。
    private var boardCells: [BoardCell] {
        var cells = engine.cards.map(BoardCell.card)
        if engine.deck.hasCenterLogo {
            let center = (MemoryTuning.columns * engine.deck.rows) / 2
            cells.insert(.logo, at: min(center, cells.count))
        }
        return cells
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

    /// 「もういちど」で呼ばれる。演出の状態を戻してから、同じ種類で盤面を作り直す。
    private func playAgain() {
        resetEffects()
        engine.start()
        withAnimation(.easeInOut(duration: 0.3)) { stage = .playing }
    }

    /// 結果画面の「カードを えらぶ」で呼ばれる。スタート画面に戻り、いまの種類をえらんだ状態にする。
    private func backToStart() {
        resetEffects()
        selectedDeck = engine.deck
        withAnimation(.easeInOut(duration: 0.3)) { stage = .start }
    }

    /// クリア演出の状態を元に戻す。
    private func resetEffects() {
        showConfetti   = false
        showCongrats   = false
        restoreOpacity = false
        rewardPopups   = []
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
    let label:          Text
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
        .accessibilityLabel(label)
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

        case .text(let text, let number):
            // ★ 長い英単語（September など）も1行に収める ★
            //   minimumScaleFactor で、カードの幅に収まるまで文字を小さくする。
            Text(verbatim: text)
                // 漢字（3文字まで）は大きめ、英単語（3〜9文字）は小さめにする
                .font(.system(size: side * (text.count > 3 ? 0.26 : 0.32),   // ← 変更可（辺長に対する文字の比率）
                              weight: .heavy, design: .rounded))
                .foregroundStyle(DS.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.2)
                .padding(.horizontal, side * 0.07)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                // 月のカードには、左上に小さく月の数字を添える（英語や漢字が読めない人のため）
                .overlay(alignment: .topLeading) {
                    if let number {
                        Text(verbatim: "\(number)")
                            .font(.system(size: side * 0.18, weight: .bold, design: .rounded))   // ← 変更可（数字の大きさ）
                            .foregroundStyle(DS.muted)
                            .padding(.leading, side * 0.09)
                            .padding(.top, side * 0.05)
                    }
                }

        case .image(let image):
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .clipShape(RoundedRectangle(cornerRadius: MemoryTuning.cardCornerRadius))
        }
    }
}


// MARK: - MemoryLogoCell

/// 5×5 の盤面のまん中に置く、Flying Dev Lab のロゴ（外周の輪と、内側の家でひと組）。押せない飾り。
///
/// ★ 輪の外側を透明にする方法 ★
///   ロゴの画像（fdl-logo-mark・fdl-logo-ring）は、どちらも白い背景の四角い画像。
///   輪の画像は、輪の外のふちが画像のふちにぴったり接しているので、
///   全体を円（Circle）の形で切り抜けば、輪の外側の白い角だけが消えて透明になる。
///   画像そのものは作り直さずに済む（タイトル画面のロゴも、同じ2枚の画像を重ねている）。
private struct MemoryLogoCell: View {
    let side: CGFloat

    var body: some View {
        ZStack {
            Image("fdl-logo-mark")
                .resizable()
                .scaledToFit()
                .padding(side * 0.12)   // ← 変更可（輪と家の隙間。小さいほど家が大きくなる）
            Image("fdl-logo-ring")
                .resizable()
                .scaledToFit()
                // multiply: 輪の画像の白い部分を透かして、下の家を見せる（タイトル画面と同じ手法）
                .blendMode(.multiply)
        }
        .background(Color.white)   // 輪の内側は白（かべがみの上でも、ロゴがはっきり見えるように）
        .clipShape(Circle())       // 輪の外側の白い角を切り落として、透明にする
        .frame(width: side, height: side)
        .shadow(color: .black.opacity(0.12), radius: 4, x: 0, y: 2)
        .allowsHitTesting(false)
        .accessibilityHidden(true)   // 飾りなので読み上げない
    }
}
