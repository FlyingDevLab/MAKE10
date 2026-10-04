//
//  ThanksNotebookStore.swift
//  FDL-TenBlitz
//
//  Created by 空飛ぶ研究室(FlyingDevLab) on 2026/10/04.
//
//  ありがとう てちょう の記録を持ち、保存するシングルトン。
//  毎日のページ（ミッションとチェック）・ごほうびの受け渡し・引き直し・リセットを担当する。
//
//  役割分担:
//    - ThanksNotebookStore（このファイル）: 記録の読み書きと、ごほうびの計算
//    - ThanksNotebookModels               : ミッション・相手・1日分のページの定義と、日替わりの選び方
//    - ThanksNotebookView など            : 見た目と操作
//    - EnergyStore                        : ごほうびのエネルギーを残高に足す
//
//  ★ 1日の区切り ★
//    端末の 0時（DayKey を参照。シールやさんの入れ替えと同じ）。
//    その日に初めて手帳を開いたときに、その日のページ（3つのミッション）を作って保存する。
//    保存するので、開き直しても同じミッションが並ぶ。

import Foundation

// MARK: - ThanksNotebookStore

// @Observable / シングルトンの解説は AppSettings.swift 冒頭を参照
@Observable
final class ThanksNotebookStore {

    static let shared = ThanksNotebookStore()

    /// 日付（"2026-10-04"）ごとのページ。
    private(set) var pages: [String: ThanksDayPage] = [:]

    private init() { load() }

    // MARK: きょうのページ

    /// きょうのページ。まだ無ければ作って保存する（手帳を開いたとき・日付が変わったときに呼ぶ）。
    @discardableResult
    func openToday(now: Date = Date()) -> ThanksDayPage {
        let key = DayKey.string(for: now)
        if let page = pages[key] { return page }
        let page = ThanksDayPage.makeNew()
        pages[key] = page
        save()
        return page
    }

    /// 指定した日のページ（無ければ nil）。
    func page(on date: Date) -> ThanksDayPage? {
        pages[DayKey.string(for: date)]
    }

    // MARK: チェック

    /// きょうのミッションをチェックする。チェックの数が増えたら、その分のごほうびを渡す。
    /// - Parameter people: 相手（相手を選ばないミッションは空）
    /// - Returns: 今回渡したごほうび（kcal）。渡さなかったら 0。
    @discardableResult
    func check(_ mission: ThanksMission, people: [ThanksPerson], now: Date = Date()) -> Double {
        let key = DayKey.string(for: now)
        guard var page = pages[key], page.missions.contains(mission) else { return 0 }
        page.checks[mission] = people

        // ★ ごほうびは「その日のチェック数」で決まる ★
        //   1個 → 合計10、2個 → 合計30、3個（全部）→ 合計100（ThanksTuning.rewardTotals）。
        //   これまでに渡した段階（rewardedStage）より増えたときだけ、その差分を渡す。
        //   チェックを外して付け直しても段階は増えないので、二重には渡らない。
        var reward: Double = 0
        let stage = page.checkedCount
        if stage > page.rewardedStage,
           ThanksTuning.rewardTotals.indices.contains(stage) {
            reward = ThanksTuning.rewardTotals[stage] - ThanksTuning.rewardTotals[page.rewardedStage]
            page.rewardedStage = stage
        }

        pages[key] = page
        save()
        // 保存してから渡す（どちらもその場で保存されるので、演出の途中で終了しても消えない）
        if reward > 0 { EnergyStore.shared.grantGift(reward) }
        return reward
    }

    /// きょうのミッションのチェックを外す（押しまちがえたとき用）。
    /// もらったエネルギーは減らさない。
    func uncheck(_ mission: ThanksMission, now: Date = Date()) {
        let key = DayKey.string(for: now)
        guard var page = pages[key] else { return }
        page.checks[mission] = nil
        pages[key] = page
        save()
    }

    /// まだチェックしていないミッションを入れ替える（引き直し）。
    func reroll(now: Date = Date()) {
        let key = DayKey.string(for: now)
        guard var page = pages[key] else { return }
        page.reroll()
        pages[key] = page
        save()
    }

    // MARK: まとめ（集計）

    /// まとめの期間。
    enum SummaryPeriod: String, CaseIterable, Identifiable {
        case all        // いままで ぜんぶ
        case thisMonth  // こんげつ
        var id: String { rawValue }
    }

    /// 期間内にチェックしたミッションの集計。
    struct Summary {
        /// できたミッションの合計の数。
        var total = 0
        /// ミッションごとの回数。
        var byMission: [ThanksMission: Int] = [:]
        /// 相手ごとの回数（1つのミッションで2人選んでいたら、それぞれ1回）。
        var byPerson: [ThanksPerson: Int] = [:]
    }

    /// 期間内の集計を作る。
    func summary(for period: SummaryPeriod, now: Date = Date()) -> Summary {
        var result = Summary()
        // ★ 日付の文字列で期間を判定する ★
        //   キーは "2026-10-04" の形なので、今月の分は "2026-10-" で始まるかどうかで分かる。
        let monthPrefix = String(DayKey.string(for: now).prefix(8))
        for (key, page) in pages where period == .all || key.hasPrefix(monthPrefix) {
            for mission in page.missions {
                guard let people = page.checks[mission] else { continue }
                result.total += 1
                result.byMission[mission, default: 0] += 1
                for person in people { result.byPerson[person, default: 0] += 1 }
            }
        }
        return result
    }

    // MARK: リセット

    /// 「さいしょから はじめる」で、手帳の記録をすべて消す。
    func reset() {
        pages = [:]
        UserDefaults.standard.removeObject(forKey: UDKey.thanksNotebook)
    }

    // MARK: 保存／読み込み

    private func save() {
        guard let data = try? JSONEncoder().encode(pages) else { return }
        UserDefaults.standard.set(data, forKey: UDKey.thanksNotebook)
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: UDKey.thanksNotebook),
              let saved = try? JSONDecoder().decode([String: ThanksDayPage].self, from: data) else { return }
        pages = saved
    }
}
