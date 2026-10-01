//
//  StickerShopView.swift
//  FDL-TenBlitz
//
//  Created by 空飛ぶ研究室(FlyingDevLab) on 2026/10/01.
//
//  シールやさん（ショップ）の画面。その日の10種類のシールを棚に並べ、
//  エネルギーを使って1種類1枚ずつ買える。全部売り切れたら閉店する。
//
//  役割分担:
//    - StickerShopView（このファイル）: 棚の表示・購入の確認・売り切れ／閉店の表示と演出
//    - StickerShop                   : 品揃え・売り切れ・閉店の状態（この画面は呼び出すだけ）
//    - EnergyStore / EnergyBadge     : 残高の判定と表示
//
//  ★ このファイルの構成 ★
//    StickerShopView … 画面本体（残高・棚・閉店カード・確認カード・メッセージ・紙吹雪）
//    ShopShelfCell   … 棚の1マス（シール1種類分）

import SwiftUI

// MARK: - StickerShopView

struct StickerShopView: View {

    // MARK: 設定項目（呼び出し側から渡すパラメータ）

    /// 閉店中に「ガチャを まわす」が押されたときの処理。nil のときはボタンを出さない。
    var onOpenGacha: (() -> Void)? = nil

    // MARK: 依存

    private let shop   = StickerShop.shared
    private let energy = EnergyStore.shared

    /// アプリが前面に戻ってきたことを知るための値（日付が変わっていれば品揃えを入れ替える）。
    @Environment(\.scenePhase) private var scenePhase

    // MARK: 調整用の定数

    /// 棚の列数。10種類を 5列×2段 で並べる。
    private let columnCount: Int     = 5      // ← 変更可
    /// 「シールばこに いれたよ」などのメッセージを出しておく時間（秒）。
    private let toastDuration: Double = 1.8   // ← 変更可
    /// 買い占めの紙吹雪を出しておく時間（秒）。
    private let confettiDuration: Double = 3.5  // ← 変更可

    // MARK: ローカル状態

    /// 購入確認カードに出しているシール。nil のときはカードを出さない。
    @State private var selectedEmoji: String? = nil
    /// 画面下部に一時的に出すメッセージ。
    @State private var toast: LocalizedStringKey? = nil
    /// メッセージの世代番号。続けて出したとき、前のメッセージの消去で新しい方を消さないようにする。
    // 世代番号パターンの解説は GameViewModel.swift を参照
    @State private var toastGeneration = 0
    /// 買い占めの紙吹雪を出しているか。
    @State private var showsConfetti = false

    // MARK: body

    var body: some View {
        ZStack {
            VStack(spacing: 16) {
                header

                if shop.isClosed {
                    closedCard
                        .transition(.scale(scale: 0.9).combined(with: .opacity))
                } else {
                    shelf
                    remainingText
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)

            if let emoji = selectedEmoji {
                confirmOverlay(emoji: emoji)
                    .transition(.opacity)
                    .zIndex(10)
            }

            if let toast {
                VStack {
                    Spacer()
                    toastView(toast)
                        .padding(.bottom, 24)
                }
                .transition(.opacity.combined(with: .move(edge: .bottom)))
                .allowsHitTesting(false)
                .zIndex(20)
            }

            if showsConfetti {
                ConfettiView(isSpecial: true)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
                    .zIndex(30)
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: shop.isClosed)
        .animation(.easeInOut(duration: 0.2), value: selectedEmoji)
        .onAppear { shop.openShop() }
        .onChange(of: scenePhase) { _, phase in
            // 寝る前に開いたまま翌朝アプリへ戻ってきた、などのときに品揃えを入れ替える
            if phase == .active { shop.openShop() }
        }
    }

    // MARK: サブビュー（上部）

    /// 残高と値段の案内。
    private var header: some View {
        VStack(spacing: 6) {
            EnergyBadge(showsLabel: true, fontSize: 22)
            HStack(spacing: 4) {
                Text("shop_price_each")
                Text(verbatim: "🔥 \(EnergyStore.format(EnergyTuning.shopPrice))kcal")
                    .foregroundStyle(DS.energy)
            }
            .font(.system(size: 14, weight: .bold, design: .rounded))
            .foregroundStyle(DS.textBody)
            Text("shop_daily_hint")
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(DS.muted)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: DS.sectionRadius)
                .fill(DS.card)
                .shadow(color: .black.opacity(0.06), radius: 10, x: 0, y: 4)
        )
    }

    // MARK: サブビュー（棚）

    /// その日の10種類を並べた棚。
    private var shelf: some View {
        LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: columnCount),
            spacing: 8
        ) {
            ForEach(shop.lineup, id: \.self) { emoji in
                ShopShelfCell(emoji: emoji, isSoldOut: shop.isSoldOut(emoji)) {
                    SoundManager.shared.playTap()
                    selectedEmoji = emoji
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: DS.sectionRadius)
                .fill(DS.card)
                .shadow(color: .black.opacity(0.06), radius: 10, x: 0, y: 4)
        )
    }

    /// 「のこり 7 / 10」の表示。
    private var remainingText: some View {
        let total = shop.lineup.count
        let left  = shop.lineup.filter { !shop.isSoldOut($0) }.count
        return Text("shop_remaining \(left) \(total)")
            .font(.system(size: 14, weight: .bold, design: .rounded))
            .foregroundStyle(DS.muted)
    }

    // MARK: サブビュー（閉店）

    /// 全部売り切れたときのカード。次の開店までの時間と、ガチャへの案内を出す。
    private var closedCard: some View {
        VStack(spacing: 12) {
            // 🏪 は iOS では「24」と書かれたコンビニの絵になり、閉店と矛盾するので使わない
            Text(verbatim: "🌙")
                .font(.system(size: 56))
            Text("shop_closed_title")
                .font(.system(size: 26, weight: .black, design: .rounded))
                .foregroundStyle(DS.primary)
            Text("shop_closed_message")
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(DS.textBody)
                .multilineTextAlignment(.center)

            // ★ TimelineView とは？ ★
            //   決まった間隔で中身を描き直してくれるコンテナ View。
            //   ここでは30秒ごとに「つぎの かいてんまで あと◯じかん◯ふん」を計算し直している。
            //   タイマーを自分で作って止める手間がなく、画面を離れれば自動で止まる。
            TimelineView(.periodic(from: .now, by: 30)) { context in
                nextOpenText(now: context.date)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(DS.muted)
            }

            if let onOpenGacha {
                Button {
                    SoundManager.shared.vibrate()
                    SoundManager.shared.playTap()
                    onOpenGacha()
                } label: {
                    Text("shop_go_gacha")
                        .font(.system(size: 17, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(
                            RoundedRectangle(cornerRadius: DS.btnRadius)
                                .fill(DS.energy)
                                .shadow(color: DS.energy.opacity(0.35), radius: 8, x: 0, y: 4)
                        )
                }
                .buttonStyle(.plain)
                .padding(.top, 4)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: DS.cardRadius)
                .fill(DS.card)
                .shadow(color: .black.opacity(0.06), radius: 10, x: 0, y: 4)
        )
    }

    /// 次の開店（翌日0時）までの残り時間の文言。1時間を切ったら分だけにする。
    private func nextOpenText(now: Date) -> Text {
        let seconds = max(0, Int(shop.nextRestock(after: now).timeIntervalSince(now)))
        let hours   = seconds / 3600
        let minutes = max(1, (seconds % 3600) / 60)   // 「あと0ふん」と出ないよう最低1分にする
        return hours > 0
            ? Text("shop_next_open_hours \(hours) \(minutes)")
            : Text("shop_next_open_minutes \(minutes)")
    }

    // MARK: サブビュー（購入の確認）

    /// 棚のシールをタップしたときに出すカード。
    /// 売り切れ・エネルギー不足・購入確認のどれかを出し分ける。
    private func confirmOverlay(emoji: String) -> some View {
        let isSoldOut = shop.isSoldOut(emoji)
        let canAfford = energy.canAfford(EnergyTuning.shopPrice)

        return ZStack {
            // カードの外をタップしても閉じられるようにする
            Color.black.opacity(0.35)
                .ignoresSafeArea()
                .onTapGesture { selectedEmoji = nil }

            VStack(spacing: 14) {
                Text(emoji)
                    .font(.system(size: 88))

                if isSoldOut {
                    Text("shop_sold_out")
                        .font(.system(size: 20, weight: .black, design: .rounded))
                        .foregroundStyle(DS.muted)
                    closeButton
                } else if canAfford {
                    Text("shop_confirm_title")
                        .font(.system(size: 20, weight: .black, design: .rounded))
                        .foregroundStyle(DS.textPrimary)
                    Text(verbatim: "🔥 \(EnergyStore.format(EnergyTuning.shopPrice))kcal")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundStyle(DS.energy)
                    HStack(spacing: 12) {
                        closeButton
                        Button {
                            purchase(emoji)
                        } label: {
                            Text("shop_confirm_buy")
                                .font(.system(size: 18, weight: .black, design: .rounded))
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(
                                    RoundedRectangle(cornerRadius: DS.btnRadius)
                                        .fill(DS.energy)
                                        .shadow(color: DS.energy.opacity(0.35), radius: 8, x: 0, y: 4)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                } else {
                    let shortage = EnergyTuning.shopPrice - energy.balance
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
                    closeButton
                }
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

    /// 確認カードの「やめる」「とじる」ボタン。
    private var closeButton: some View {
        Button {
            SoundManager.shared.playTap()
            selectedEmoji = nil
        } label: {
            Text("shop_confirm_cancel")
                .font(.system(size: 18, weight: .semibold, design: .rounded))
                .foregroundStyle(DS.muted)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(
                    RoundedRectangle(cornerRadius: DS.btnRadius)
                        .fill(Color.black.opacity(0.05))
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: サブビュー（メッセージ）

    private func toastView(_ text: LocalizedStringKey) -> some View {
        Text(text)
            .font(.system(size: 15, weight: .bold, design: .rounded))
            .foregroundStyle(.white)
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .background(Capsule().fill(Color.black.opacity(0.72)))
    }

    // MARK: 購入

    /// シールを買い、結果に応じてメッセージや演出を出す。
    private func purchase(_ emoji: String) {
        let result = shop.buy(emoji)
        selectedEmoji = nil

        switch result {
        case .purchased:
            SoundManager.shared.vibrate()
            if shop.isClosed {
                // 最後の1枚 = 買い占め。いつもより派手に祝う
                SoundManager.shared.playSpecial()
                showToast("shop_buyout")
                celebrate()
            } else {
                SoundManager.shared.playUnlock()
                showToast("memory_result_saved")   // 「シールばこに いれたよ」（どうぶつめくりと共用）
            }
        case .notEnoughEnergy:
            // 確認カードを出した後にエネルギーが減ることは通常ないが、念のため
            showToast("shop_not_enough")
        case .soldOut:
            showToast("shop_sold_out")
        case .notInLineup:
            // 画面を開いたまま品揃えが入れ替わった場合。新しい品揃えを読み込み直す
            shop.openShop()
            showToast("shop_restocked")
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

    /// 買い占めの紙吹雪を出し、しばらくしたら消す。
    private func celebrate() {
        showsConfetti = true
        DispatchQueue.main.asyncAfter(deadline: .now() + confettiDuration) {
            showsConfetti = false
        }
    }
}

// MARK: - ShopShelfCell

/// 棚の1マス。シールを大きく出し、売り切れなら薄くして「うりきれ」の札を重ねる。
private struct ShopShelfCell: View {
    let emoji:     String
    let isSoldOut: Bool
    let onTap:     () -> Void

    var body: some View {
        Button(action: onTap) {
            Text(emoji)
                .font(.system(size: 36))   // ← 変更可（棚のシールの大きさ）
                .frame(maxWidth: .infinity)
                .aspectRatio(1, contentMode: .fit)
                .background(
                    RoundedRectangle(cornerRadius: DS.rowRadius)
                        .fill(DS.choiceFill)
                )
                .opacity(isSoldOut ? 0.35 : 1.0)
                .overlay {
                    if isSoldOut {
                        Text("shop_sold_out")
                            .font(.system(size: 10, weight: .black, design: .rounded))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 3)
                            .background(Capsule().fill(DS.blitzColor))
                            .rotationEffect(.degrees(-12))
                    }
                }
        }
        .buttonStyle(.plain)
        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isSoldOut)
    }
}
