//
//  BreakReminderView.swift
//  FDL-TenBlitz
//
//  Created by 空飛ぶ研究室(FlyingDevLab) on 2026/10/04.
//
//  続けて遊んだ時間が長くなったときに、休憩をうながすカード。タイトル画面の上に重ねて出す。
//  指（👆）がひょこっと現れて「30ぷん あそんだよ」と声をかける。
//  休み方のひとこと（目を休める・のびをする・水を飲む）は、出すたびに1つ選ぶ。
//
//  役割分担は BreakReminder.swift 冒頭を参照。

import SwiftUI

// MARK: - BreakReminderView

struct BreakReminderView: View {

    // MARK: 設定項目（呼び出し側から渡すパラメータ）

    /// 「◯ぷん あそんだよ」の分数。
    let minutes: Int
    /// 「わかった」が押されたときの処理。
    let onClose: () -> Void

    // MARK: 表示内容

    /// 休み方のひとこと。出すたびに1つ選ぶ。
    private static let tips: [LocalizedStringKey] = [
        "break_tip_eyes",
        "break_tip_stretch",
        "break_tip_water",
    ]

    // MARK: ローカル状態

    /// 表示中のひとこと（出たときに1つ選んで固定する）。
    @State private var tip: LocalizedStringKey = BreakReminderView.tips.randomElement() ?? "break_tip_eyes"
    /// カードのポップイン用。
    @State private var scale: CGFloat = 0.8
    /// 指が下から現れる演出用。
    @State private var fingerOffset: CGFloat = 40
    /// 指がゆらゆら動く演出用。
    @State private var fingerBob = false

    // MARK: body

    var body: some View {
        ZStack {
            Color.black.opacity(0.35)
                .ignoresSafeArea()

            VStack(spacing: 14) {
                Text(verbatim: "👆")
                    .font(.system(size: 64))   // ← 変更可（指の大きさ）
                    .offset(y: fingerOffset + (fingerBob ? -6 : 0))
                    .accessibilityHidden(true)

                Text("break_title \(minutes)")
                    .font(.system(size: 24, weight: .black, design: .rounded))
                    .foregroundStyle(DS.textPrimary)
                    .multilineTextAlignment(.center)

                Text(tip)
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundStyle(DS.textBody)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                Button {
                    SoundManager.shared.playTap()
                    onClose()
                } label: {
                    Text("break_ok")
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
                .padding(.top, 4)
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
        }
        .onAppear {
            SoundManager.shared.playUnlock()
            withAnimation(.spring(response: 0.45, dampingFraction: 0.65)) { scale = 1.0 }
            // 指が下からひょこっと現れ、そのあと上下にゆらゆら動き続ける
            withAnimation(.spring(response: 0.5, dampingFraction: 0.55).delay(0.15)) { fingerOffset = 0 }
            withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true).delay(0.7)) {
                fingerBob = true
            }
        }
    }
}
