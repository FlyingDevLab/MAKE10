//
//  EnergyRewardBanner.swift
//  FDL-TenBlitz
//
//  Created by 空飛ぶ研究室(FlyingDevLab) on 2026/10/01.
//
//  結果画面に埋め込むだけで「今回のプレイで増えたエネルギー」を見せられる共通部品。
//  数字が 0 から駆け上がる演出で、クリア後にエネルギーがドサっと増える体験をつくる。
//
//  役割分担:
//    - EnergyRewardBanner（このファイル）: 今回の獲得量の表示と演出
//    - EnergyStore                       : 今回の獲得量（sessionEarned / sessionClearBonus）を持つ
//    - 各ゲームの結果画面                  : EnergyRewardBanner() を1行差し込むだけ
//
//  ★ 呼び出し側が1行で済む理由 ★
//    表示する値は EnergyStore から自分で読み、演出も .task の中で完結させているため、
//    結果画面に @State や onAppear を追加する必要がない。
//
//  ★ エネルギーはこの画面より前に加算済み ★
//    残高への加算は各ゲームが終了した瞬間に済ませてある（EnergyStore 冒頭を参照）。
//    このバナーは「いくら増えたか」を見せる演出だけを担当し、残高には触らない。
//    そのため、演出の途中で画面を離れてもエネルギーが失われることはない。

import SwiftUI

// MARK: - EnergyRewardBanner

struct EnergyRewardBanner: View {

    // MARK: 依存

    private let energy = EnergyStore.shared

    // MARK: 調整用の定数

    /// 結果カードのポップインを待ってから数え始めるまでの時間（秒）。
    private let startDelay:    Double = 0.45   // ← 変更可
    /// 0 から獲得量まで数え上げる時間（秒）。
    private let countDuration: Double = 0.9    // ← 変更可
    /// 数え上げのコマ数。多いほど滑らかになる。
    private let countSteps:    Int    = 30     // ← 変更可

    // MARK: ローカル状態

    /// 今回プレイ中に増えた量（kcal）。表示開始時に EnergyStore から読み取る。
    @State private var playKcal:  Double = 0
    /// 今回のクリアボーナス（kcal）。表示開始時に EnergyStore から読み取る。
    @State private var bonusKcal: Double = 0
    /// いま画面に出している数字（kcal）。0 から playKcal + bonusKcal まで駆け上がる。
    @State private var shownKcal: Double = 0
    /// 数え終わった瞬間に数字を一瞬大きくする演出用のフラグ。
    @State private var isBumped:  Bool   = false

    private var totalKcal: Double { playKcal + bonusKcal }

    // MARK: body

    var body: some View {
        VStack(spacing: 0) {
            // ★ この 0 サイズの土台を置いている理由 ★
            //   獲得量が 0 のときにコンテナの中身が空になると、.task の付く先が無くなり
            //   一度も実行されない（＝獲得量を読み取れずバナーが永久に出ない）。
            //   常に実体のある子を1つ置くことで .task の実行を保証する。
            Color.clear.frame(width: 0, height: 0)

            if totalKcal > 0 {
                card
                    .transition(.scale(scale: 0.85).combined(with: .opacity))
            }
        }
        .task { await playCountUp() }
    }

    // MARK: サブビュー

    /// バナー本体。「エネルギー🔥」「+42kcal」と、必要なら内訳を出す。
    private var card: some View {
        VStack(spacing: 4) {
            HStack(spacing: 2) {
                Text("energy_label")
                Text(verbatim: "🔥")
            }
            .font(.system(size: 15, weight: .black, design: .rounded))
            .foregroundStyle(DS.energy)

            // 単位の kcal は全言語共通なので、ローカライズせずそのまま出す
            Text(verbatim: "+\(EnergyStore.format(shownKcal))kcal")
                .font(.system(size: 34, weight: .black, design: .rounded))
                .monospacedDigit()   // 数え上げ中に数字の幅が変わって左右に揺れないようにする
                .foregroundStyle(DS.energy)
                .scaleEffect(isBumped ? 1.18 : 1.0)   // ← 変更可（数え終わりの膨らみ）

            breakdown
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 20)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: DS.sectionRadius)
                .fill(DS.card)
                .shadow(color: DS.energy.opacity(0.15), radius: 10, x: 0, y: 4)
        )
        .padding(.horizontal, 28)
        .padding(.bottom, 8)
    }

    /// 内訳の行。クリアボーナスがあるときだけ出す。
    ///   ・プレイ中の獲得もある → 「あそんだぶん +12 ・ クリアの ごほうび +118」と両方を並べる
    ///   ・クリアボーナスだけ   → 「クリアボーナス」の文字だけ（数字は上の大きな数字と同じなので出さない）
    @ViewBuilder
    private var breakdown: some View {
        if bonusKcal > 0 {
            HStack(spacing: 10) {
                if playKcal > 0 {
                    breakdownItem("energy_reward_play", kcal: playKcal)
                    Text(verbatim: "・")
                    breakdownItem("energy_reward_clear_bonus", kcal: bonusKcal)
                } else {
                    Text("energy_reward_clear_bonus")
                }
            }
            .font(.system(size: 12, weight: .bold, design: .rounded))
            .foregroundStyle(DS.muted)
        }
    }

    private func breakdownItem(_ label: LocalizedStringKey, kcal: Double) -> some View {
        HStack(spacing: 3) {
            Text(label)
            Text(verbatim: "+\(EnergyStore.format(kcal))")
                .monospacedDigit()
        }
    }

    // MARK: 演出

    /// 獲得量を読み取り、0 から数え上げる。画面を離れると .task ごと自動でキャンセルされる。
    private func playCountUp() async {
        let play  = energy.sessionEarned
        let bonus = energy.sessionClearBonus
        guard play + bonus > 0 else { return }

        withAnimation(.spring(response: 0.4, dampingFraction: 0.65)) {
            playKcal  = play
            bonusKcal = bonus
        }

        try? await Task.sleep(for: .seconds(startDelay))
        let total = play + bonus
        for step in 1...countSteps {
            guard !Task.isCancelled else { return }
            // 最初は速く、終わりに向かってゆっくりになる（ease-out）と「ドサっと入った」感じが出る
            let t = Double(step) / Double(countSteps)
            shownKcal = total * (1 - pow(1 - t, 3))
            try? await Task.sleep(for: .seconds(countDuration / Double(countSteps)))
        }
        shownKcal = total   // 計算の誤差で端数がずれないよう、最後は正確な値に揃える

        // 数え終わりに数字を一瞬膨らませ、振動で「入った」ことを手にも伝える
        SoundManager.shared.vibrate()
        withAnimation(.spring(response: 0.18, dampingFraction: 0.5)) { isBumped = true }
        try? await Task.sleep(for: .seconds(0.18))
        withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) { isBumped = false }
    }
}
