//
//  UpdateGiftNoticeView.swift
//  FDL-TenBlitz
//
//  Created by 空飛ぶ研究室(FlyingDevLab) on 2026/10/01.
//
//  アップデートしてくれた人に、プレゼントしたエネルギーを知らせるカード。
//  1.5.0 に更新した後の最初の起動で1回だけ、タイトル画面の上に重ねて出す。
//  もらったエネルギーをすぐ使えるよう、ガチャ・シールやさんへ移るボタンも置く。
//
//  役割分担:
//    - UpdateGiftNoticeView（このファイル）: お知らせの見た目と紙吹雪
//    - AppMigration                        : プレゼントを渡し、お知らせを出すかどうかを決める
//    - MakeTenContentView                  : いつ重ねて出し、いつ消すか

import SwiftUI

// MARK: - UpdateGiftNoticeView

struct UpdateGiftNoticeView: View {

    // MARK: 設定項目（呼び出し側から渡すパラメータ）

    /// 「ガチャ」が押されたときの処理（お知らせを消して画面を移るのは呼び出し側が行う）。
    let onOpenGacha: () -> Void
    /// 「シールやさん」が押されたときの処理。
    let onOpenShop: () -> Void
    /// 「とじる」が押されたときの処理。
    let onClose: () -> Void

    // MARK: ローカル状態

    /// カードのポップインアニメーション用。
    @State private var scale: CGFloat = 0.8

    // MARK: body

    var body: some View {
        ZStack {
            Color.black.opacity(0.35)
                .ignoresSafeArea()

            VStack(spacing: 14) {
                Text(verbatim: "🎁")
                    .font(.system(size: 64))
                Text("update_gift_title")
                    .font(.system(size: 22, weight: .black, design: .rounded))
                    .foregroundStyle(DS.textPrimary)
                    .multilineTextAlignment(.center)
                VStack(spacing: 4) {
                    HStack(spacing: 2) {
                        Text("energy_label")
                        Text(verbatim: "🔥")
                    }
                    .font(.system(size: 15, weight: .black, design: .rounded))
                    // 単位の kcal は全言語共通なので、ローカライズせずそのまま出す
                    Text(verbatim: "+\(EnergyStore.format(AppMigrationTuning.updateGift150))kcal")
                        .font(.system(size: 34, weight: .black, design: .rounded))
                        .monospacedDigit()
                }
                .foregroundStyle(DS.energy)
                Text("update_gift_message")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(DS.textBody)
                    .multilineTextAlignment(.center)
                Text("update_gift_janken_note")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(DS.muted)
                    .multilineTextAlignment(.center)

                // もらったエネルギーをすぐ使えるよう、ガチャとシールやさんへの近道を置く
                HStack(spacing: 12) {
                    actionButton("gacha_title", systemImage: "gift", action: onOpenGacha)
                    actionButton("shop_title",  systemImage: "storefront", action: onOpenShop)
                }
                .padding(.top, 4)

                Button {
                    SoundManager.shared.playTap()
                    onClose()
                } label: {
                    Text("gacha_close")   // 「とじる」（ガチャ画面と共用）
                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                        .foregroundStyle(DS.muted)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: DS.btnRadius)
                                .fill(Color.black.opacity(0.05))
                        )
                }
                .buttonStyle(.plain)
            }
            .padding(24)
            .frame(maxWidth: 340)
            .background(
                RoundedRectangle(cornerRadius: DS.dialogRadius)
                    .fill(DS.card)
                    .shadow(color: .black.opacity(0.15), radius: 20, x: 0, y: 8)
            )
            .padding(.horizontal, 28)
            .scaleEffect(scale)

            // 紙吹雪はカードより手前に重ね、タップは下へ素通しさせる。
            // isSpecial（金・白・銀）だと白いカードの上で白い粒が見えなくなるので、虹色の通常版を使う
            ConfettiView(isSpecial: false)
                .ignoresSafeArea()
                .allowsHitTesting(false)
        }
        .onAppear {
            SoundManager.shared.playSpecial()
            withAnimation(.spring(response: 0.45, dampingFraction: 0.65)) { scale = 1.0 }
        }
    }

    // MARK: サブビュー

    /// ガチャ・シールやさんへ移るボタン。
    private func actionButton(
        _ titleKey: LocalizedStringKey,
        systemImage: String,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            SoundManager.shared.vibrate()
            SoundManager.shared.playTap()
            action()
        } label: {
            Label(titleKey, systemImage: systemImage)
                .font(.system(size: 17, weight: .black, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
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
}
