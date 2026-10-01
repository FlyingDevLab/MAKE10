//
//  EnergyBadge.swift
//  FDL-TenBlitz
//
//  Created by 空飛ぶ研究室(FlyingDevLab) on 2026/10/01.
//
//  いまのエネルギー残高を「🔥 1,100.8kcal」の形で表示する共通部品。
//  ヘッダー（SharedFrame）に常に出しておき、ショップ・ガチャ画面でも使う。
//
//  役割分担:
//    - EnergyBadge（このファイル）: 残高の表示と、増えたときのアニメーション
//    - EnergyStore               : 残高を持つ（この部品は読むだけ）
//
//  ★ 残高が変わると自動で表示が変わる理由 ★
//    EnergyStore は @Observable なので、body の中で balance を読むだけで
//    SwiftUI がその値を見張ってくれる。プレイ中に正解して earn() が呼ばれると、
//    どの画面にいてもこの部品が再描画され、数字がその場で増える。

import SwiftUI

// MARK: - EnergyBadge

struct EnergyBadge: View {

    // MARK: 設定項目（呼び出し側から渡すパラメータ）

    /// 先頭に「エネルギー」の文字を付けるか。
    /// ヘッダーは幅が狭いので付けず、ショップ・ガチャ画面では付ける。
    var showsLabel: Bool = false

    /// 文字の大きさ（pt）。
    var fontSize: CGFloat = 13

    // MARK: 依存

    private let energy = EnergyStore.shared

    // MARK: ローカル状態

    /// 残高が増えた瞬間に数字を一瞬大きくする演出用のフラグ。
    @State private var isBumped = false

    // MARK: body

    var body: some View {
        HStack(spacing: 3) {
            if showsLabel {
                Text("energy_label")
            }
            Text(verbatim: "🔥")
            // 単位の kcal は全言語共通なので、ローカライズせずそのまま出す
            Text(verbatim: "\(EnergyStore.format(energy.balance))kcal")
                .monospacedDigit()   // 桁の幅をそろえ、数字が変わるたびに左右へ揺れないようにする
                // ★ .contentTransition(.numericText) とは？ ★
                //   数字が変わったとき、変わった桁だけを上下にスライドさせて切り替える演出。
                //   value に今の数を渡すと、増えたか減ったかでスライドの向きも変わる。
                //   実際に動かすには、値の変化を .animation で包む必要がある（下の .animation）。
                .contentTransition(.numericText(value: energy.balance))
        }
        .font(.system(size: fontSize, weight: .bold, design: .rounded))
        .foregroundStyle(DS.energy)
        .lineLimit(1)
        .scaleEffect(isBumped ? 1.15 : 1.0)   // ← 変更可（増えたときの膨らみ）
        .animation(.spring(response: 0.35, dampingFraction: 0.7), value: energy.balanceDeci)
        .onChange(of: energy.balanceDeci) { old, new in
            // 減ったとき（ガチャ・ショップで使ったとき）は膨らませない
            guard new > old else { return }
            bump()
        }
        // VoiceOver では「エネルギー 1,100.8 kcal」と1つの値として読み上げる
        .accessibilityElement(children: .combine)
    }

    // MARK: 演出

    /// 数字を一瞬膨らませて元に戻す。
    private func bump() {
        withAnimation(.spring(response: 0.18, dampingFraction: 0.5)) { isBumped = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) { isBumped = false }
        }
    }
}
