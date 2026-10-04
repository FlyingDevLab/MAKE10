//
//  StickerShop.swift
//  FDL-TenBlitz
//
//  Created by 空飛ぶ研究室(FlyingDevLab) on 2026/10/01.
//
//  エネルギーを使って、好きなシールを選んで買える「ショップ」の状態管理。
//  毎日10種類のシールが並び、1種類につき1枚まで買える。全部売り切れたら閉店する。
//
//  役割分担:
//    - StickerShop（このファイル）: その日の品揃え・売り切れ・閉店の管理と永続化
//    - EnergyStore                : エネルギーの消費
//    - StickerStore               : 買ったシールの保管（ストレージへ直送）と所有数の集計
//    - ショップ画面                 : 品揃えの表示と購入操作（このファイルは画面に関与しない）
//
//  ★ 品揃えの決め方 ★
//    その日に初めてショップを開いたとき（openShop）に10種類を決めて保存し、
//    同じ日のあいだは固定する。日付が変わってから次に開いたときに入れ替わる。
//      ・救済枠（3種類）  : 持っている枚数が少ないシールほど選ばれやすい重み付きの抽選
//      ・ランダム枠（7種類）: 全シールから均等に抽選（救済枠と同じものは選ばない）
//    開くたびに選び直さないのは、救済枠が「持っている枚数」で決まるため。
//    選び直すと、1枚買っただけで（その1枚が「持っている」側に移り）並びが変わってしまう。
//
//  ★ 端末の時計を変えたら？ ★
//    日付は端末の時計で判断しているので、時計を進めれば品揃えを入れ替えられる。
//    課金のないアプリで、得をするのも自分だけなので、防ぐ仕組みは入れていない。

import Foundation

// MARK: - StickerShop

// @Observable / シングルトンの解説は AppSettings.swift 冒頭を参照
@Observable
final class StickerShop {

    static let shared = StickerShop()

    // MARK: その日の状態

    /// その日の品揃えと売り切れの記録。UserDefaults に JSON で保存する。
    // Codable の解説は GamePickerComponents.swift を参照
    struct DailyState: Codable, Equatable {
        /// 品揃えを決めた日（"2026-10-01" の形）。今日と違えば入れ替える。
        var day:     String
        /// 並んでいるシール（表示順）。
        var lineup:  [String]
        /// 売り切れたシール。
        var soldOut: Set<String>
    }

    /// 購入の結果。ショップ画面が表示の出し分けに使う。
    enum PurchaseResult {
        /// 買えた。シールはストレージに入った。
        case purchased
        /// エネルギーが足りない。
        case notEnoughEnergy
        /// そのシールはもう売り切れ。
        case soldOut
        /// 今日の品揃えにないシール（画面を開いたまま日付が変わった場合など）。
        case notInLineup
    }

    // MARK: 状態

    /// その日の状態。openShop() を呼ぶまで、前回保存した状態（または nil）のまま。
    private(set) var state: DailyState?

    // MARK: 表示用の値

    /// 並んでいるシール（表示順）。
    var lineup: [String] { state?.lineup ?? [] }

    /// 指定したシールが売り切れかどうか。
    func isSoldOut(_ emoji: String) -> Bool {
        state?.soldOut.contains(emoji) ?? false
    }

    /// 全部売り切れて閉店しているかどうか。
    var isClosed: Bool {
        guard let state, !state.lineup.isEmpty else { return false }
        return state.lineup.allSatisfy { state.soldOut.contains($0) }
    }

    /// 次に品揃えが入れ替わる時刻（翌日の0時）。閉店中の「つぎの かいてんまで」表示に使う。
    func nextRestock(after now: Date = .now) -> Date {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        return calendar.date(byAdding: .day, value: 1, to: today) ?? now
    }

    // MARK: 初期化

    private init() { load() }

    // MARK: 開店

    /// ショップを開いたときに呼ぶ。日付が変わっていれば、新しい品揃えで開店する。
    /// 同じ日のうちは何もしない（品揃えと売り切れはそのまま）。
    func openShop(now: Date = .now) {
        let today = DayKey.string(for: now)
        guard state?.day != today else { return }

        var rng = SystemRandomNumberGenerator()
        let lineup = Self.makeLineup(
            catalog: StickerCatalog.all,
            owned:   StickerStore.shared.ownedCounts(),
            using:   &rng
        )
        state = DailyState(day: today, lineup: lineup, soldOut: [])
        save()
    }

    // MARK: 購入

    /// シールを1枚買う。買えたらストレージへ直送し、売り切れにする。
    /// シールを渡してからエネルギーを減らす順の理由は StickerGacha.pull を参照。
    func buy(_ emoji: String) -> PurchaseResult {
        guard var current = state, current.lineup.contains(emoji) else { return .notInLineup }
        guard !current.soldOut.contains(emoji) else { return .soldOut }

        let energy = EnergyStore.shared
        guard energy.canAfford(EnergyTuning.shopPrice) else { return .notEnoughEnergy }

        StickerStore.shared.addStickerToStorage(emoji: emoji)
        current.soldOut.insert(emoji)
        state = current
        save()
        energy.spend(EnergyTuning.shopPrice)
        return .purchased
    }

    // MARK: リセット

    /// 進捗リセット時に品揃えと売り切れを消す。次に開いたときに新しい品揃えで開店する。
    func reset() {
        state = nil
        UserDefaults.standard.removeObject(forKey: UDKey.stickerShopState)
        UserDefaults.standard.removeObject(forKey: UDKey.shopTipIndex)   // 「ひとこと」も1話目から
    }

    // MARK: 品揃えの抽選

    /// その日の品揃えを決める（救済枠＋ランダム枠をまぜて並べる）。
    ///
    /// ★ 乱数生成器（RandomNumberGenerator）を引数で受け取る理由 ★
    ///   ふだんは SystemRandomNumberGenerator（毎回ちがう乱数）を渡すが、
    ///   動作確認のときに「決まった乱数」を渡せば、同じ品揃えを何度でも再現できる。
    ///   inout は「渡した生成器の中身（乱数の進み具合）をこの関数が書き換える」という印。
    /// - Parameters:
    ///   - catalog: 全シール
    ///   - owned:   シールごとの所有数（StickerStore.ownedCounts）
    ///   - rng:     乱数生成器
    /// - Returns: 並べるシール（最大 救済枠 + ランダム枠 種類）
    static func makeLineup<R: RandomNumberGenerator>(
        catalog: [String],
        owned:   [String: Int],
        using rng: inout R
    ) -> [String] {
        var remaining = catalog

        // ── 救済枠：持っている枚数が少ないほど選ばれやすい ──────────
        var rescue: [String] = []
        for _ in 0..<EnergyTuning.shopRescueSlots {
            guard let index = weightedIndex(in: remaining, owned: owned, using: &rng) else { break }
            rescue.append(remaining.remove(at: index))
        }

        // ── ランダム枠：残りから均等に選ぶ ─────────────────────────
        remaining.shuffle(using: &rng)
        let random = remaining.prefix(EnergyTuning.shopRandomSlots)

        // 救済枠がいつも先頭に来ると「どれが救済枠か」が分かってしまうので、まぜて並べる
        return (rescue + random).shuffled(using: &rng)
    }

    /// 重み付きで1つ選び、そのインデックスを返す。候補が空なら nil。
    /// 重み = 1 ÷ (持っている枚数 + 1) ^ rescueWeightExponent
    ///
    /// ★ 重み付きの抽選のしくみ ★
    ///   全候補の重みを合計し、0〜合計 のあいだの数をランダムに1つ決める。
    ///   重みを先頭から順に足していき、その数を超えたところの候補を選ぶ。
    ///   重みが大きい候補ほど「数直線上の幅」が広いので、当たりやすくなる。
    private static func weightedIndex<R: RandomNumberGenerator>(
        in candidates: [String],
        owned:         [String: Int],
        using rng:     inout R
    ) -> Int? {
        guard !candidates.isEmpty else { return nil }
        let weights = candidates.map { emoji in
            1.0 / pow(Double(owned[emoji, default: 0] + 1), EnergyTuning.rescueWeightExponent)
        }
        let total = weights.reduce(0, +)
        var target = Double.random(in: 0..<total, using: &rng)
        for (index, weight) in weights.enumerated() {
            target -= weight
            if target < 0 { return index }
        }
        // 小数の誤差で最後まで 0 未満にならなかったときは、最後の候補にする
        return candidates.count - 1
    }

    // MARK: 保存／読み込み

    private func save() {
        guard let state else { return }
        do {
            let data = try JSONEncoder().encode(state)
            UserDefaults.standard.set(data, forKey: UDKey.stickerShopState)
        } catch {
            print("⚠️ StickerShop: 品揃えの保存に失敗: \(error.localizedDescription)")
        }
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: UDKey.stickerShopState) else { return }
        do {
            state = try JSONDecoder().decode(DailyState.self, from: data)
        } catch {
            // 読めなかった場合は state が nil のまま。次に開いたときに新しい品揃えで開店する
            print("⚠️ StickerShop: 品揃えの読み込みに失敗: \(error.localizedDescription)")
        }
    }
}
