//
//  ThanksTodayView.swift
//  FDL-TenBlitz
//
//  Created by 空飛ぶ研究室(FlyingDevLab) on 2026/10/04.
//
//  ありがとう てちょう の「きょう」のページ。その日の3つのミッションを並べ、チェックできる。
//
//  ★ このファイルの構成 ★
//    ThanksTodayView     … ページ本体（ごほうびの目安・ミッション・引き直し・演出）
//    ThanksMissionRow    … ミッション1つの行
//    ThanksPersonPicker  … 「あいては だれ？」を選ぶカード（複数えらべる）
//    ThanksUncheckDialog … チェックを外すときの確認カード
//
//  ★ 操作の流れ ★
//    まだのミッションをタップ → 相手を選ぶミッションなら ThanksPersonPicker → 「できた！」でチェック
//                              → 相手を選ばないミッションなら、その場でチェック
//    チェック済みをタップ     → ThanksUncheckDialog（押しまちがえたとき用）

import SwiftUI

// MARK: - ThanksTodayView

struct ThanksTodayView: View {

    // MARK: 依存

    private let store = ThanksNotebookStore.shared

    /// アプリが前面に戻ってきたことを知るための値（日付が変わっていれば新しいページにする）。
    @Environment(\.scenePhase) private var scenePhase

    // MARK: ローカル状態

    /// 相手を選んでいるミッション。nil のときは選ぶカードを出さない。
    @State private var pickingFor: ThanksMission? = nil
    /// チェックを外すか確かめているミッション。
    @State private var uncheckingFor: ThanksMission? = nil
    /// いま浮かべている「+◯kcal」。
    @State private var rewardPopup: RewardPopup? = nil
    /// 全部できたときの紙吹雪。
    @State private var showsConfetti = false
    /// 日付が変わったら描き直すための、きょうの日付。
    @State private var today = Date()

    /// 浮かべる「+◯kcal」1つ分。同じ量が続いても演出をやり直せるよう id を持たせる。
    private struct RewardPopup: Identifiable, Equatable {
        let id = UUID()
        let kcal: Double
        let isComplete: Bool
    }

    // MARK: body

    var body: some View {
        let page = store.page(on: today) ?? ThanksDayPage(missions: [], checks: [:], rewardedStage: 0)

        ZStack {
            ScrollView {
                VStack(spacing: 16) {
                    header(page: page)

                    VStack(spacing: 12) {
                        ForEach(page.missions) { mission in
                            ThanksMissionRow(
                                mission: mission,
                                people:  page.checks[mission],
                                onTap:   { tap(mission, page: page) }
                            )
                        }
                    }

                    rerollButton(page: page)
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 24)
            }

            if let reward = rewardPopup {
                rewardPopupView(reward)
                    .id(reward.id)
                    .transition(.scale(scale: 0.6).combined(with: .opacity))
                    .allowsHitTesting(false)
                    .zIndex(5)
            }

            if let mission = pickingFor {
                ThanksPersonPicker(mission: mission) { people in
                    pickingFor = nil
                    check(mission, people: people)
                } onCancel: {
                    pickingFor = nil
                }
                .transition(.opacity)
                .zIndex(10)
            }

            if let mission = uncheckingFor {
                ThanksUncheckDialog(mission: mission) {
                    store.uncheck(mission)
                    uncheckingFor = nil
                } onCancel: {
                    uncheckingFor = nil
                }
                .transition(.opacity)
                .zIndex(10)
            }

            if showsConfetti {
                ConfettiView(isSpecial: false)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
                    .zIndex(30)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: pickingFor)
        .animation(.easeInOut(duration: 0.2), value: uncheckingFor)
        .animation(.spring(response: 0.35, dampingFraction: 0.6), value: rewardPopup)
        .onAppear { openToday() }
        .onChange(of: scenePhase) { _, phase in
            // 寝る前に開いたまま翌朝戻ってきた、などのときに新しいページにする
            if phase == .active { openToday() }
        }
    }

    // MARK: サブビュー

    /// 日付と、ごほうびの目安（チェック数ごとの合計）。
    private func header(page: ThanksDayPage) -> some View {
        VStack(spacing: 10) {
            Text(today, format: .dateTime.month().day().weekday())
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(DS.muted)

            // ★ 文字を使わずに目安を見せる ★
            //   「✅ +10 → ✅✅ +30 → 💮 +100」のように絵と数字だけで並べ、どの言語でも同じ見た目にする。
            //   いまのチェック数まで届いた段は色を濃くする。
            HStack(spacing: 8) {
                ForEach(1...ThanksTuning.missionsPerDay, id: \.self) { stage in
                    rewardStep(stage: stage, reached: page.checkedCount >= stage)
                }
            }
            .padding(.horizontal, 14)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: DS.sectionRadius)
                .fill(DS.card)
                .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 3)
        )
    }

    /// ごほうびの目安の1段。
    private func rewardStep(stage: Int, reached: Bool) -> some View {
        let isLast = stage == ThanksTuning.missionsPerDay
        let mark   = isLast ? "💮" : String(repeating: "✅", count: stage)
        let kcal   = ThanksTuning.rewardTotals.indices.contains(stage) ? ThanksTuning.rewardTotals[stage] : 0
        return VStack(spacing: 2) {
            Text(verbatim: mark)
                .font(.system(size: 18))
            // 単位の kcal は全言語共通なので、ローカライズせずそのまま出す
            Text(verbatim: "+\(EnergyStore.format(kcal))")
                .font(.system(size: 14, weight: .black, design: .rounded))
                .foregroundStyle(DS.energy)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: DS.chipRadius)
                .fill(reached ? DS.energy.opacity(0.16) : DS.muted.opacity(0.06))
        )
        .opacity(reached ? 1 : 0.6)
        .animation(.easeOut(duration: 0.25), value: reached)
    }

    /// 引き直しボタン。まだのミッションだけを入れ替える。全部できた日は出さない。
    @ViewBuilder
    private func rerollButton(page: ThanksDayPage) -> some View {
        if !page.isComplete {
            Button {
                SoundManager.shared.playTap()
                withAnimation(.spring(response: 0.45, dampingFraction: 0.75)) {
                    store.reroll()
                }
            } label: {
                Label("thanks_reroll", systemImage: "arrow.triangle.2.circlepath")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(DS.muted)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .background(Capsule().fill(Color.black.opacity(0.05)))
            }
            .buttonStyle(.plain)
            .padding(.top, 4)
        } else {
            Text("thanks_complete")
                .font(.system(size: 20, weight: .black, design: .rounded))
                .foregroundStyle(DS.energy)
                .padding(.top, 4)
        }
    }

    /// チェックしたときに浮かべる「+◯kcal」。全部できたときは大きく出す。
    private func rewardPopupView(_ reward: RewardPopup) -> some View {
        VStack(spacing: 4) {
            if reward.isComplete {
                Text(verbatim: "💮")
                    .font(.system(size: 72))
                Text("thanks_complete")
                    .font(.system(size: 22, weight: .black, design: .rounded))
                    .foregroundStyle(DS.textPrimary)
            }
            Text(verbatim: "🔥 +\(EnergyStore.format(reward.kcal))kcal")
                .font(.system(size: reward.isComplete ? 34 : 26, weight: .black, design: .rounded))
                .foregroundStyle(DS.energy)
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 18)
        .background(
            RoundedRectangle(cornerRadius: DS.dialogRadius)
                .fill(DS.card)
                .shadow(color: DS.energy.opacity(0.25), radius: 14, x: 0, y: 6)
        )
    }

    // MARK: 操作

    /// きょうのページを開く（無ければ作る）。日付が変わっていれば表示もきょうに切り替える。
    private func openToday() {
        today = Date()
        store.openToday(now: today)
    }

    /// ミッションの行をタップしたとき。
    private func tap(_ mission: ThanksMission, page: ThanksDayPage) {
        SoundManager.shared.playTap()
        if page.isChecked(mission) {
            uncheckingFor = mission
        } else if mission.asksWho {
            pickingFor = mission
        } else {
            check(mission, people: [])
        }
    }

    /// チェックして、ごほうびがあれば演出を出す。
    private func check(_ mission: ThanksMission, people: [ThanksPerson]) {
        // 開いたまま日付が変わっていたら、きのうのページではなく新しいページにする
        if DayKey.string(for: Date()) != DayKey.string(for: today) {
            openToday()
            return
        }
        let reward = withAnimation(.spring(response: 0.35, dampingFraction: 0.6)) {
            store.check(mission, people: people)
        }
        SoundManager.shared.vibrate()

        let isComplete = store.page(on: today)?.isComplete ?? false
        guard reward > 0 else {
            SoundManager.shared.playCorrect()
            return
        }
        isComplete ? SoundManager.shared.playSpecial() : SoundManager.shared.playUnlock()
        let popup = RewardPopup(kcal: reward, isComplete: isComplete)
        rewardPopup = popup
        if isComplete { showsConfetti = true }

        // ← 変更可：「+◯kcal」を出しておく時間（秒）
        DispatchQueue.main.asyncAfter(deadline: .now() + (isComplete ? 2.4 : 1.4)) {
            if rewardPopup == popup { rewardPopup = nil }
        }
        if isComplete {
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.5) { showsConfetti = false }
        }
    }
}

// MARK: - ThanksMissionRow

/// ミッション1つの行。チェック済みなら花丸スタンプと、選んだ相手を出す。
private struct ThanksMissionRow: View {
    let mission: ThanksMission
    /// チェックした相手。nil ならまだチェックしていない。
    let people:  [ThanksPerson]?
    let onTap:   () -> Void

    private var isChecked: Bool { people != nil }

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 14) {
                Text(verbatim: mission.emoji)
                    .font(.system(size: 40))
                    .frame(width: 56)

                VStack(alignment: .leading, spacing: 6) {
                    Text(mission.titleKey)
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        .foregroundStyle(DS.textPrimary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    if let people, !people.isEmpty {
                        Text(verbatim: people.map(\.emoji).joined(separator: " "))
                            .font(.system(size: 20))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                // チェック欄。チェック済みは花丸スタンプがポンと押される
                ZStack {
                    Circle()
                        .stroke(DS.muted.opacity(0.35), lineWidth: 2.5)
                        .frame(width: 40, height: 40)
                    if isChecked {
                        Text(verbatim: "💮")
                            .font(.system(size: 44))
                            .transition(.scale(scale: 2.2).combined(with: .opacity))
                    }
                }
                .frame(width: 48)
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: DS.sectionRadius)
                    .fill(isChecked ? DS.energy.opacity(0.08) : DS.card)
                    .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 3)
            )
            .overlay(
                RoundedRectangle(cornerRadius: DS.sectionRadius)
                    .stroke(isChecked ? DS.energy.opacity(0.5) : .clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
        .transition(.asymmetric(
            insertion: .move(edge: .trailing).combined(with: .opacity),
            removal:   .move(edge: .leading).combined(with: .opacity)
        ))
    }
}

// MARK: - ThanksPersonPicker

/// 「あいては だれ？」を選ぶカード。複数えらべる。1人も選んでいないあいだは「できた！」を押せない。
private struct ThanksPersonPicker: View {
    let mission:  ThanksMission
    let onDone:   ([ThanksPerson]) -> Void
    let onCancel: () -> Void

    @State private var selected: Set<ThanksPerson> = []

    private let columns = [GridItem(.flexible(), spacing: 10),
                           GridItem(.flexible(), spacing: 10),
                           GridItem(.flexible(), spacing: 10)]

    var body: some View {
        ZStack {
            Color.black.opacity(0.35)
                .ignoresSafeArea()
                .onTapGesture(perform: onCancel)

            VStack(spacing: 16) {
                Text(verbatim: mission.emoji)
                    .font(.system(size: 44))
                Text("thanks_who_title")
                    .font(.system(size: 22, weight: .black, design: .rounded))
                    .foregroundStyle(DS.textPrimary)

                LazyVGrid(columns: columns, spacing: 10) {
                    // 選んだ順ではなく、いつも同じ並び（ThanksPerson の宣言順）で出す
                    ForEach(ThanksPerson.allCases) { person in
                        personChip(person)
                    }
                }

                HStack(spacing: 12) {
                    Button {
                        SoundManager.shared.playTap()
                        onCancel()
                    } label: {
                        Text("reset_confirm_cancel")   // 「やめる」（設定のリセット確認と共用）
                            .font(.system(size: 17, weight: .semibold, design: .rounded))
                            .foregroundStyle(DS.muted)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(RoundedRectangle(cornerRadius: DS.btnRadius).fill(Color.black.opacity(0.05)))
                    }
                    .buttonStyle(.plain)

                    Button {
                        // 並びは宣言順にそろえて保存する（集計や表示で順番がぶれないように）
                        onDone(ThanksPerson.allCases.filter { selected.contains($0) })
                    } label: {
                        Text("thanks_who_done")
                            .font(.system(size: 17, weight: .black, design: .rounded))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(
                                RoundedRectangle(cornerRadius: DS.btnRadius)
                                    .fill(selected.isEmpty ? DS.muted.opacity(0.35) : DS.energy)
                            )
                    }
                    .buttonStyle(.plain)
                    .disabled(selected.isEmpty)
                }
            }
            .padding(22)
            .frame(maxWidth: 420)
            .background(
                RoundedRectangle(cornerRadius: DS.dialogRadius)
                    .fill(DS.card)
                    .shadow(color: .black.opacity(0.15), radius: 20, x: 0, y: 8)
            )
            .padding(.horizontal, 20)
        }
    }

    private func personChip(_ person: ThanksPerson) -> some View {
        let isOn = selected.contains(person)
        return Button {
            SoundManager.shared.playTap()
            if isOn { selected.remove(person) } else { selected.insert(person) }
        } label: {
            VStack(spacing: 4) {
                Text(verbatim: person.emoji)
                    .font(.system(size: 32))
                Text(person.nameKey)
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(DS.textBody)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: DS.chipRadius)
                    .fill(isOn ? DS.energy.opacity(0.16) : DS.choiceFill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: DS.chipRadius)
                    .stroke(isOn ? DS.energy : DS.muted.opacity(0.15), lineWidth: isOn ? 2.5 : 1)
            )
            .scaleEffect(isOn ? 1.04 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.6), value: isOn)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - ThanksUncheckDialog

/// チェックを外すか確かめるカード。外しても、もらったエネルギーは減らない。
private struct ThanksUncheckDialog: View {
    let mission:   ThanksMission
    let onConfirm: () -> Void
    let onCancel:  () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.35)
                .ignoresSafeArea()
                .onTapGesture(perform: onCancel)

            VStack(spacing: 16) {
                Text(verbatim: mission.emoji)
                    .font(.system(size: 44))
                Text("thanks_uncheck_title")
                    .font(.system(size: 20, weight: .black, design: .rounded))
                    .foregroundStyle(DS.textPrimary)
                    .multilineTextAlignment(.center)

                HStack(spacing: 12) {
                    Button {
                        SoundManager.shared.playTap()
                        onCancel()
                    } label: {
                        Text("reset_confirm_cancel")   // 「やめる」
                            .font(.system(size: 17, weight: .semibold, design: .rounded))
                            .foregroundStyle(DS.muted)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(RoundedRectangle(cornerRadius: DS.btnRadius).fill(Color.black.opacity(0.05)))
                    }
                    .buttonStyle(.plain)

                    Button {
                        SoundManager.shared.playTap()
                        onConfirm()
                    } label: {
                        Text("thanks_uncheck_button")
                            .font(.system(size: 17, weight: .black, design: .rounded))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(RoundedRectangle(cornerRadius: DS.btnRadius).fill(DS.gaugeWarn))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(22)
            .frame(maxWidth: 340)
            .background(
                RoundedRectangle(cornerRadius: DS.dialogRadius)
                    .fill(DS.card)
                    .shadow(color: .black.opacity(0.15), radius: 20, x: 0, y: 8)
            )
            .padding(.horizontal, 28)
        }
    }
}
