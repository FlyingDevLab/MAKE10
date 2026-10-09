//
//  GachaView.swift
//  FDL-TenBlitz
//
//  Created by 空飛ぶ研究室(FlyingDevLab) on 2026/10/01.
//
//  ガチャの画面。エネルギーを使って、ランダムなシールを1回（100kcal）または
//  10連（1,000kcal・おまけ1枚付き）で手に入れる。全シールが同じ確率で出る。
//
//  役割分担:
//    - GachaView（このファイル）: マシンの演出・ボタン・結果の表示
//    - StickerGacha             : 値段の確認・抽選・シールの受け渡し（この画面は呼び出すだけ）
//    - EnergyStore / EnergyBadge: 残高の判定と表示
//
//  ★ 抽選は演出の「前」に済ませている ★
//    ボタンを押した瞬間に StickerGacha.pull でエネルギーを使い、シールもストレージへ入れる。
//    そのあとで回す演出と結果を見せるので、演出の途中で画面を離れても
//    「エネルギーだけ減ってシールが手に入らない」ことは起きない。
//
//  ★ このファイルの構成 ★
//    GachaView         … 画面本体（残高・マシン・ボタン・結果カード・メッセージ）
//    GachaResultItem   … 結果1枚分の表示用データ（NEW・おまけの印）
//    GachaMachineView  … ガチャマシンの絵と、回したときの揺れ・ハンドルの回転
//    GachaResultCell   … 結果カードの1マス

import SwiftUI

// MARK: - GachaView

struct GachaView: View {

    // MARK: 依存

    private let energy = EnergyStore.shared

    // MARK: 調整用の定数

    /// ハンドルを回してから結果を出すまでの時間（秒）。マシンの揺れとカプセルの落下を見せる。
    private let spinDuration:  Double = 1.3   // ← 変更可
    /// 結果を1枚ずつ出す間隔（秒）。10連のときに順番にめくれていくように見せる。
    private let revealStagger: Double = 0.12  // ← 変更可
    /// 画面下部のメッセージを出しておく時間（秒）。
    private let toastDuration: Double = 1.8   // ← 変更可
    /// 10連の結果で紙吹雪を出しておく時間（秒）。
    private let confettiDuration: Double = 3.5  // ← 変更可

    // MARK: ローカル状態

    /// 回した回数。増えるたびにマシンが揺れる（GachaMachineView のアニメーションのきっかけ）。
    @State private var spinCount = 0
    /// 演出中かどうか。演出中はボタンを押せなくする（連打で何回も回らないように）。
    @State private var isSpinning = false
    /// 出てきたカプセル（結果を出す直前の演出用）。
    @State private var showsCapsule = false
    /// 結果カードに出すシール。nil のときはカードを出さない。
    @State private var results: [GachaResultItem]? = nil
    /// 結果カードで表示済みの枚数（1枚ずつめくる演出用）。
    @State private var revealedCount = 0
    /// エネルギー不足のカードを出しているときの、足りないまわし方。
    @State private var shortagePull: StickerGacha.Pull? = nil
    /// 画面下部に一時的に出すメッセージ。
    @State private var toast: LocalizedStringKey? = nil
    /// メッセージの世代番号（世代番号パターンの解説は GameViewModel.swift を参照）。
    @State private var toastGeneration = 0
    /// 10連の結果で紙吹雪を出しているか。
    @State private var showsConfetti = false
    /// 紙吹雪の世代番号。続けて10連を回したとき、前回の消去で今回の紙吹雪を消さないようにする。
    @State private var confettiGeneration = 0

    // MARK: body

    /// この画面が使える場所の大きさ（回転・分割表示・Duo の開閉のたびに測り直す）。
    @State private var areaSize: CGSize = .zero

    // ★ 横長の場所では、ガチャのマシンとボタンを左右に並べる理由 ★
    //   縦に積んだままだと、iPad を横にしたときなどに高さが足りず、マシンが小さくなり、ボタンもはみ出しやすい。
    //   左にマシン、右に残高とボタンを置けば、マシンを高さいっぱいの大きさで描ける。
    //   どちらにするかは端末の向きではなく「使える場所が横長かどうか」で決める（DS.isWide）。
    var body: some View {
        ZStack {
            Group {
                if DS.isWide(areaSize) {
                    HStack(spacing: 20) {
                        GachaMachineView(spinCount: spinCount, showsCapsule: showsCapsule)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                        VStack(spacing: 14) {
                            header
                            pullButtons
                        }
                        .frame(maxWidth: .infinity)
                    }
                    // ヘッダーの下にぶら下がるエネルギー残高と重ならないよう、少し下げる
                    .padding(.top, 20)      // ← 変更可
                    .padding(.bottom, 12)
                } else {
                    VStack(spacing: 14) {
                        header

                        GachaMachineView(spinCount: spinCount, showsCapsule: showsCapsule)
                            .frame(maxHeight: .infinity)

                        pullButtons
                            .padding(.bottom, 12)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .onGeometryChange(for: CGSize.self) { proxy in
                proxy.size
            } action: { size in
                areaSize = size
            }

            if let results {
                resultOverlay(results)
                    .transition(.opacity)
                    .zIndex(10)
            }

            if let pull = shortagePull {
                shortageOverlay(pull)
                    .transition(.opacity)
                    .zIndex(10)
            }

            // 紙吹雪は結果カードより手前に重ね、タップは下へ素通しさせる（「とじる」を押せるように）。
            // isSpecial（金・白・銀）だと白い結果カードの上で白い粒が見えなくなるので、虹色の通常版を使う
            if showsConfetti {
                ConfettiView(isSpecial: false)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
                    .zIndex(15)
            }

            if let toast {
                VStack {
                    Spacer()
                    Text(toast)
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .background(Capsule().fill(Color.black.opacity(0.72)))
                        .padding(.bottom, 24)
                }
                .transition(.opacity.combined(with: .move(edge: .bottom)))
                .allowsHitTesting(false)
                .zIndex(20)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: results == nil)
        .animation(.easeInOut(duration: 0.2), value: shortagePull == nil)
    }

    // MARK: サブビュー（上部）

    /// 残高と、確率の説明。
    private var header: some View {
        VStack(spacing: 6) {
            EnergyBadge(showsLabel: true, fontSize: 22)
            // ⚠️ 変更注意: 「全シールが同じ確率」は StickerGacha.draw の仕様と一致させること
            Text("gacha_odds \(StickerCatalog.all.count)")
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(DS.muted)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: DS.sectionRadius)
                .fill(DS.card)
                .shadow(color: .black.opacity(0.06), radius: 10, x: 0, y: 4)
        )
    }

    // MARK: サブビュー（ボタン）

    /// 「1かい まわす」「10れん まわす」のボタン。
    private var pullButtons: some View {
        HStack(spacing: 12) {
            pullButton(.single, label: "gacha_pull_single", subLabel: nil)
            pullButton(.ten, label: "gacha_pull_ten", subLabel: "gacha_ten_bonus")
        }
    }

    private func pullButton(
        _ pull: StickerGacha.Pull,
        label: LocalizedStringKey,
        subLabel: LocalizedStringKey?
    ) -> some View {
        let canAfford = energy.canAfford(pull.price)
        return Button {
            spin(pull)
        } label: {
            VStack(spacing: 3) {
                Text(label)
                    .font(.system(size: 17, weight: .black, design: .rounded))
                Text(verbatim: "🔥 \(EnergyStore.format(pull.price))kcal")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                if let subLabel {
                    Text(subLabel)
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(.white.opacity(0.25)))
                }
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: 84)
            .background(
                RoundedRectangle(cornerRadius: DS.btnRadius)
                    // 足りないときも押せる（押すと「あと◯kcal」を教える）が、見た目は控えめにする
                    .tintFill(canAfford ? DS.energy : DS.muted.opacity(0.45))
                    .shadow(color: canAfford ? DS.energy.opacity(0.35) : .clear, radius: 8, x: 0, y: 4)
            )
        }
        .buttonStyle(.plain)
        .disabled(isSpinning)
    }

    // MARK: サブビュー（結果）

    /// 出たシールを並べるカード。1枚ずつめくれるように表示していく。
    private func resultOverlay(_ items: [GachaResultItem]) -> some View {
        ZStack {
            Color.black.opacity(0.35)
                .ignoresSafeArea()

            VStack(spacing: 16) {
                Text("gacha_result_title")
                    .font(.system(size: 22, weight: .black, design: .rounded))
                    .foregroundStyle(DS.textPrimary)

                if items.count == 1, let item = items.first {
                    GachaResultCell(item: item, isRevealed: revealedCount >= 1, size: 96)
                } else {
                    LazyVGrid(
                        columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4),
                        spacing: 10
                    ) {
                        ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                            GachaResultCell(item: item, isRevealed: index < revealedCount, size: 40)
                        }
                    }
                }

                Text("memory_result_saved")   // 「シールばこに いれたよ」（どうぶつめくりと共用）
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(DS.muted)

                Button {
                    SoundManager.shared.playTap()
                    results = nil
                } label: {
                    Text("gacha_close")
                        .font(.system(size: 18, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(
                            RoundedRectangle(cornerRadius: DS.btnRadius)
                                .fill(DS.primary)
                                .shadow(color: DS.primary.opacity(0.35), radius: 8, x: 0, y: 4)
                        )
                }
                .buttonStyle(.plain)
                // 全部めくり終わるまでは閉じられないようにする（演出の見逃し防止）
                .disabled(revealedCount < items.count)
                .opacity(revealedCount < items.count ? 0.5 : 1)
            }
            .padding(24)
            .frame(maxWidth: 340)
            .background(
                RoundedRectangle(cornerRadius: DS.dialogRadius)
                    .fill(DS.card)
                    .shadow(color: .black.opacity(0.15), radius: 20, x: 0, y: 8)
            )
            .padding(.horizontal, 24)
        }
    }

    /// エネルギーが足りないときのカード。ショップと同じ文言を使う。
    private func shortageOverlay(_ pull: StickerGacha.Pull) -> some View {
        let shortage = pull.price - energy.balance
        return ZStack {
            Color.black.opacity(0.35)
                .ignoresSafeArea()
                .onTapGesture { shortagePull = nil }

            VStack(spacing: 14) {
                Text(verbatim: "🔥")
                    .font(.system(size: 64))
                Text("shop_not_enough")
                    .font(.system(size: 20, weight: .black, design: .rounded))
                    .foregroundStyle(DS.textPrimary)
                Text("shop_need_more \(EnergyStore.formatShortage(shortage))")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(DS.energy)
                Text("shop_not_enough_hint")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(DS.muted)
                    .multilineTextAlignment(.center)
                Button {
                    SoundManager.shared.playTap()
                    shortagePull = nil
                } label: {
                    Text("gacha_close")
                        .font(.system(size: 18, weight: .semibold, design: .rounded))
                        .foregroundStyle(DS.muted)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(
                            RoundedRectangle(cornerRadius: DS.btnRadius)
                                .tintFill(Color.black.opacity(0.05))
                        )
                }
                .buttonStyle(.plain)
            }
            .padding(24)
            .frame(maxWidth: 320)
            .background(
                RoundedRectangle(cornerRadius: DS.dialogRadius)
                    .fill(DS.card)
                    .shadow(color: .black.opacity(0.15), radius: 20, x: 0, y: 8)
            )
            .padding(.horizontal, 28)
        }
    }

    // MARK: ガチャを回す

    /// ガチャを回す。足りなければ不足カードを出し、足りれば抽選してから演出を始める。
    private func spin(_ pull: StickerGacha.Pull) {
        guard !isSpinning else { return }
        SoundManager.shared.vibrate()

        guard energy.canAfford(pull.price) else {
            SoundManager.shared.playTap()
            shortagePull = pull
            return
        }

        // 「NEW」の判定のため、抽選の前に持っている枚数を控えておく
        let ownedBefore = StickerStore.shared.ownedCounts()
        guard let emojis = StickerGacha.pull(pull) else {
            showToast("shop_not_enough")
            return
        }
        let items = GachaResultItem.make(from: emojis, ownedBefore: ownedBefore, bonusCount: pull == .ten ? EnergyTuning.tenPullBonus : 0)

        // ── 演出：ハンドルが回ってマシンが揺れ、カプセルが出てくる ─────────
        isSpinning = true
        SoundManager.shared.playCoinLand()
        withAnimation(.spring(response: 0.5, dampingFraction: 0.6)) { spinCount += 1 }
        DispatchQueue.main.asyncAfter(deadline: .now() + spinDuration * 0.6) {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.55)) { showsCapsule = true }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + spinDuration) {
            showsCapsule = false
            showResults(items, isTen: pull == .ten)
        }
    }

    /// 結果カードを出し、1枚ずつめくっていく。
    private func showResults(_ items: [GachaResultItem], isTen: Bool) {
        revealedCount = 0
        results = items
        isTen ? SoundManager.shared.playSpecial() : SoundManager.shared.playUnlock()
        if isTen { celebrate() }
        for index in items.indices {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25 + revealStagger * Double(index)) {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.55)) { revealedCount = index + 1 }
                if index == items.count - 1 { isSpinning = false }
            }
        }
    }

    /// 10連の結果に紙吹雪を出し、しばらくしたら消す。
    private func celebrate() {
        confettiGeneration += 1
        let generation = confettiGeneration
        showsConfetti = true
        DispatchQueue.main.asyncAfter(deadline: .now() + confettiDuration) {
            guard generation == confettiGeneration else { return }
            showsConfetti = false
        }
    }

    /// 画面下部にメッセージを一時的に出す。
    private func showToast(_ text: LocalizedStringKey) {
        toastGeneration += 1
        let generation = toastGeneration
        withAnimation(.spring(response: 0.3)) { toast = text }
        DispatchQueue.main.asyncAfter(deadline: .now() + toastDuration) {
            guard generation == toastGeneration else { return }
            withAnimation { toast = nil }
        }
    }
}

// MARK: - GachaResultItem

/// 結果1枚分の表示用データ。
struct GachaResultItem: Identifiable {
    let id = UUID()
    let emoji:   String
    /// 初めて手に入れたシールか（「NEW」の印）。
    let isNew:   Bool
    /// 10連のおまけの1枚か（「おまけ」の印）。
    let isBonus: Bool

    /// 抽選結果から表示用データを作る。
    /// 同じ回で同じシールが2枚出たときは、最初の1枚だけを NEW にする。
    /// おまけは末尾の bonusCount 枚とする（StickerGacha は通常分のあとにおまけ分を引く）。
    static func make(from emojis: [String], ownedBefore: [String: Int], bonusCount: Int) -> [GachaResultItem] {
        var seen = Set<String>()
        return emojis.enumerated().map { index, emoji in
            let isNew = ownedBefore[emoji, default: 0] == 0 && !seen.contains(emoji)
            seen.insert(emoji)
            return GachaResultItem(
                emoji:   emoji,
                isNew:   isNew,
                isBonus: index >= emojis.count - bonusCount
            )
        }
    }
}

// MARK: - GachaMachineView

/// ガチャマシンの絵。spinCount が増えるたびに揺れてハンドルが1回転する。
private struct GachaMachineView: View {
    let spinCount:    Int
    let showsCapsule: Bool

    /// ドームの中に積まれているカプセル（色・位置・傾き）。
    /// 位置はドームの幅に対する比率（中心が 0,0。下ほど y が大きい）。
    /// 下の段ほど多く並べ、ドームの底に積み重なっているように見せる。
    private let capsules: [(color: Color, x: CGFloat, y: CGFloat, angle: Double)] = [
        // 最下段
        (DS.energy,     -0.19, 0.28,  -20), (DS.primary,   0.00, 0.29,  10), (DS.gold,     0.19, 0.28,  30),
        // 2段目
        (DS.accent,     -0.30, 0.12,   15), (DS.gaugeFull, -0.10, 0.13, -25),
        (DS.blitzColor,  0.10, 0.12,   40), (DS.primary,    0.30, 0.13, -10),
        // 3段目
        (DS.gold,       -0.20, -0.04, -35), (DS.energy,     0.00, -0.03,  20), (DS.accent,   0.20, -0.04,  -5),
        // 最上段
        (DS.gaugeFull,  -0.10, -0.20,  25), (DS.blitzColor, 0.11, -0.19, -30),
    ]

    var body: some View {
        GeometryReader { geo in
            let width = min(geo.size.width * 0.7, geo.size.height * 0.62, 260)   // ← 変更可（マシンの大きさ）
            VStack(spacing: 0) {
                dome(width: width)
                base(width: width)
            }
            .frame(width: geo.size.width, height: geo.size.height)
            // ★ keyframeAnimator とは？ ★
            //   trigger の値が変わるたびに、決めた「コマ割り（キーフレーム）」どおりに値を動かす仕組み。
            //   ここでは左右に小刻みに揺れて止まる動きを作り、マシンをガタガタ揺らしている。
            .keyframeAnimator(initialValue: 0.0, trigger: spinCount) { content, shake in
                content.offset(x: shake).rotationEffect(.degrees(shake * 0.4))
            } keyframes: { _ in
                KeyframeTrack {
                    CubicKeyframe(-8, duration: 0.08)   // ← 変更可（揺れの幅 pt）
                    CubicKeyframe(8,  duration: 0.08)
                    CubicKeyframe(-7, duration: 0.08)
                    CubicKeyframe(7,  duration: 0.08)
                    CubicKeyframe(-5, duration: 0.08)
                    CubicKeyframe(5,  duration: 0.08)
                    CubicKeyframe(-2, duration: 0.08)
                    CubicKeyframe(0,  duration: 0.08)
                }
            }
        }
    }

    /// 上のドーム（透明な丸の中にカプセルが入っている）。
    private func dome(width: CGFloat) -> some View {
        ZStack {
            Circle()
                .fill(Color.white.opacity(0.75))
                .overlay(Circle().stroke(DS.primary.opacity(0.35), lineWidth: 4))
            // カプセルを積んで置く（位置は固定。揺れはマシンごと揺れる）
            ForEach(capsules.indices, id: \.self) { i in
                let c = capsules[i]
                capsule(color: c.color, size: width * 0.2)
                    .rotationEffect(.degrees(c.angle))
                    .offset(x: c.x * width, y: c.y * width)
            }
        }
        .frame(width: width, height: width)
        .zIndex(1)
    }

    /// 下の本体（ハンドルと取り出し口）。
    private func base(width: CGFloat) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: width * 0.12)
                .fill(DS.energy)
            HStack(spacing: width * 0.12) {
                // ハンドル。回すたびに1回転する
                ZStack {
                    Circle().fill(.white)
                    Capsule()
                        .fill(DS.energy.opacity(0.8))
                        .frame(width: width * 0.05, height: width * 0.16)
                }
                .frame(width: width * 0.22, height: width * 0.22)
                .rotationEffect(.degrees(Double(spinCount) * 360))
                .animation(.easeInOut(duration: 0.6), value: spinCount)

                // 取り出し口。出てきたカプセルがここに現れる
                ZStack {
                    RoundedRectangle(cornerRadius: width * 0.05)
                        .fill(Color.black.opacity(0.25))
                    if showsCapsule {
                        capsule(color: DS.gold, size: width * 0.17)
                            .transition(.scale(scale: 0.3).combined(with: .move(edge: .top)))
                    }
                }
                .frame(width: width * 0.26, height: width * 0.2)
            }
        }
        .frame(width: width * 0.9, height: width * 0.42)
        .offset(y: -width * 0.04)   // ドームと少し重ねて一体に見せる
    }

    /// カプセル1個。上半分が色、下半分が白の丸。
    private func capsule(color: Color, size: CGFloat) -> some View {
        ZStack {
            Circle().fill(.white)
            Circle()
                .trim(from: 0.5, to: 1.0)   // 上半分だけを色で塗る
                .fill(color)
            Circle().stroke(Color.black.opacity(0.12), lineWidth: 1)
        }
        .frame(width: size, height: size)
    }
}

// MARK: - GachaResultCell

/// 結果カードの1マス。めくられるまではカプセルの「？」を出し、めくると絵文字と印を出す。
private struct GachaResultCell: View {
    let item:       GachaResultItem
    let isRevealed: Bool
    let size:       CGFloat

    var body: some View {
        ZStack {
            if isRevealed {
                Text(item.emoji)
                    .font(.system(size: size))
                    .transition(.scale(scale: 0.2).combined(with: .opacity))
            } else {
                Text(verbatim: "❔")
                    .font(.system(size: size * 0.7))
                    .opacity(0.35)
            }
        }
        .frame(width: size * 1.4, height: size * 1.4)
        .overlay(alignment: .topTrailing) {
            if isRevealed && item.isNew {
                tag("gacha_new", color: DS.blitzColor)
            }
        }
        .overlay(alignment: .bottom) {
            if isRevealed && item.isBonus {
                tag("gacha_bonus_tag", color: DS.gold)
            }
        }
    }

    private func tag(_ text: LocalizedStringKey, color: Color) -> some View {
        Text(text)
            .font(.system(size: 9, weight: .black, design: .rounded))
            .foregroundStyle(.white)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
            .background(Capsule().fill(color))
            .offset(y: 2)
    }
}
