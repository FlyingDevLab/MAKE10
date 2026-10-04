//
//  GiftNoticeView.swift
//  FDL-TenBlitz
//
//  Created by 空飛ぶ研究室(FlyingDevLab) on 2026/10/01.
//
//  エネルギーをプレゼントしたことを知らせるカード。タイトル画面の上に重ねて出す。
//  次の3種類を、同じ見た目で出し分ける。
//    ・アップデートのお礼       : 紙吹雪＋ガチャ・シールやさんへのボタン付き
//    ・はじめまして（新規インストール）: 紙吹雪＋ガチャ・シールやさんへのボタン付き
//    ・毎日のログインボーナス   : 控えめに「とじる」だけ（毎日出るので、にぎやかにしすぎない）
//
//  役割分担:
//    - GiftNoticeView（このファイル）: お知らせの見た目と演出
//    - AppMigration / DailyBonus     : エネルギーを渡し、どのお知らせを出すかを決める
//    - MakeTenContentView            : いつ重ねて出し、いつ消すか（複数あれば順番に出す）

import SwiftUI

// MARK: - GiftNotice

/// お知らせカードの種類。
enum GiftNotice: Equatable {
    /// アップデートのお礼（AppMigration を参照）。
    case updateThanks
    /// 毎日のログインボーナス・はじめまして（DailyBonus を参照）。
    case daily(DailyBonus.Notice)

    /// 一覧で区別するための識別子（カードの切り替え演出のやり直しに使う）。
    var id: String {
        switch self {
        case .updateThanks:     return "update"
        case .daily(.welcome):  return "welcome"
        case .daily(.login):    return "login"
        }
    }

    /// 紙吹雪とガチャ・シールやさんへのボタンを付けるか。
    /// 毎日のログインボーナスは毎日出るので、控えめにする。
    var celebrates: Bool {
        switch self {
        case .updateThanks, .daily(.welcome): return true
        case .daily(.login):                  return false
        }
    }
}

// MARK: - GiftNoticeView

struct GiftNoticeView: View {

    // MARK: 設定項目（呼び出し側から渡すパラメータ）

    /// 出すお知らせの種類。
    let notice: GiftNotice
    /// 「ガチャ」が押されたときの処理（お知らせを消して画面を移るのは呼び出し側が行う）。
    let onOpenGacha: () -> Void
    /// 「シールやさん」が押されたときの処理。
    let onOpenShop: () -> Void
    /// 「とじる」が押されたときの処理。
    let onClose: () -> Void

    // MARK: ローカル状態

    /// カードのポップインアニメーション用。
    @State private var scale: CGFloat = 0.8

    // MARK: 表示内容

    private var emoji: String {
        switch notice {
        case .updateThanks, .daily(.welcome): return "🎁"
        case .daily(.login):                  return "🍌"   // バナナ1本分＝ガチャ1回分
        }
    }

    private var title: LocalizedStringKey {
        switch notice {
        case .updateThanks:                  return "update_gift_title"
        case .daily(.welcome):               return "welcome_gift_title"
        case .daily(.login(_, true)):        return "login_bonus_title_streak"
        case .daily(.login(_, false)):       return "login_bonus_title"
        }
    }

    private var kcal: Double {
        switch notice {
        case .updateThanks:                  return AppMigrationTuning.updateGift150
        case .daily(.welcome):               return DailyBonusTuning.welcomeGift
        case .daily(.login(let kcal, _)):    return kcal
        }
    }

    private var message: LocalizedStringKey {
        switch notice {
        case .updateThanks, .daily(.welcome): return "update_gift_message"   // 「エネルギーを プレゼント！」（共用）
        case .daily(.login):                  return "login_bonus_message"
        }
    }

    // MARK: body

    var body: some View {
        ZStack {
            Color.black.opacity(0.35)
                .ignoresSafeArea()

            VStack(spacing: 14) {
                Text(verbatim: emoji)
                    .font(.system(size: 64))
                Text(title)
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
                    Text(verbatim: "+\(EnergyStore.format(kcal))kcal")
                        .font(.system(size: 34, weight: .black, design: .rounded))
                        .monospacedDigit()
                }
                .foregroundStyle(DS.energy)
                Text(message)
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(DS.textBody)
                    .multilineTextAlignment(.center)
                if notice == .updateThanks {
                    Text("update_gift_janken_note")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(DS.muted)
                        .multilineTextAlignment(.center)
                }

                if notice.celebrates {
                    // もらったエネルギーをすぐ使えるよう、ガチャとシールやさんへの近道を置く
                    HStack(spacing: 12) {
                        actionButton("gacha_title", systemImage: "gift", action: onOpenGacha)
                        actionButton("shop_title",  systemImage: "storefront", action: onOpenShop)
                    }
                    .padding(.top, 4)
                }

                closeButton
                    .padding(.top, notice.celebrates ? 0 : 4)
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
            if notice.celebrates {
                ConfettiView(isSpecial: false)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
            }
        }
        .onAppear {
            notice.celebrates ? SoundManager.shared.playSpecial() : SoundManager.shared.playUnlock()
            withAnimation(.spring(response: 0.45, dampingFraction: 0.65)) { scale = 1.0 }
        }
    }

    // MARK: サブビュー

    /// 「とじる」ボタン。お祝いのカードでは控えめな灰色、ログインボーナスでは主役のオレンジにする。
    private var closeButton: some View {
        Button {
            SoundManager.shared.playTap()
            onClose()
        } label: {
            Text("gacha_close")   // 「とじる」（ガチャ画面と共用）
                .font(.system(size: 17, weight: notice.celebrates ? .semibold : .black, design: .rounded))
                .foregroundStyle(notice.celebrates ? DS.muted : .white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, notice.celebrates ? 12 : 14)
                .background(
                    RoundedRectangle(cornerRadius: DS.btnRadius)
                        .tintFill(notice.celebrates ? Color.black.opacity(0.05) : DS.energy)
                )
        }
        .buttonStyle(.plain)
    }

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
