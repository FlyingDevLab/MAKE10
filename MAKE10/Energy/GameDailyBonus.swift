//
//  GameDailyBonus.swift
//  FDL-TenBlitz
//
//  Created by 空飛ぶ研究室(FlyingDevLab) on 2026/10/15.
//
//  ゲームごとの「きょう はじめての ボーナス」を管理するシングルトン。
//  その日はじめて、あるゲームを最後まで遊ぶと（結果画面が出ると）、エネルギーを少しもらえる。
//
//  役割分担:
//    - GameDailyBonus（このファイル）: どのゲームで、きょうもう受け取ったかの記録と、渡す判断
//    - 各ゲームの ViewModel             : ゲームが終わったときに claim(_:) を呼ぶ
//    - EnergyStore                      : エネルギーを渡す（grantDailyGameBonus）。iCloud にも一緒に送る
//    - EnergyRewardBanner               : 結果画面の内訳に「きょう はじめての ボーナス」を出す
//    - GamePickerTile                   : まだ受け取っていないゲームのカードに 🎁 を出す
//
//  ★ ねらい ★
//    いつも同じゲームばかりでなく、いろいろなゲームを遊んでもらうきっかけにする。
//    タイトル画面のカードに 🎁 が付いていれば「これを遊ぶとボーナスがもらえる」と分かる。
//
//  ★ 始めたときではなく、最後まで遊んだときに渡す理由 ★
//    始めただけで渡すと、始めてすぐやめるのをくり返すだけで受け取れてしまう。
//    ゲームが終わって結果画面が出たとき（クリアボーナスを渡すのと同じとき）に渡す。
//
//  ★ 1日の区切り ★
//    端末の 0時（DayKey を参照。ログインボーナス・シールやさんと同じ）。

import Foundation

// MARK: - ⚙️ 調整パラメータ（ここだけ触ればOK）

enum GameDailyBonusTuning {
    /// 1つのゲームで、その日はじめて最後まで遊んだときのボーナス（kcal）。
    /// 10種類ぜんぶ遊ぶと 1日 500。ログインボーナス（100）・ガチャ1回（100）と比べて決めた。
    static let amount: Double = 50   // ← 変更可
}

// MARK: - GameDailyBonus

// @Observable / シングルトンの解説は AppSettings.swift 冒頭を参照
@Observable
final class GameDailyBonus {

    static let shared = GameDailyBonus()

    /// ボーナスの対象になるゲーム。シールやさん・ガチャ・てちょう・シール帳・じてんは、ゲームではないので入れない。
    static let targets: Set<GamePickerSelection> = [
        .normal, .blitz, .quiz, .whackAMole, .maze,
        .pinball, .coinDrop, .janken, .tenPuzzle, .memory,
    ]

    /// ゲームごとに、最後に受け取った日（キーは GamePickerSelection の rawValue、値は "2026-10-15"）。
    /// ★ 日付で持つ理由 ★ 「きょう受け取ったか」だけを持つと、毎日 0時に消す仕組みが要る。
    ///   日付で持っておけば、きょうの日付と比べるだけで済む（消し忘れもない）。
    private(set) var claimedDays: [String: String]

    private init() {
        claimedDays = UserDefaults.standard.dictionary(forKey: Self.storageKey) as? [String: String] ?? [:]
    }

    // MARK: 判断

    /// このゲームで、きょうのボーナスがまだもらえるか（タイトル画面の 🎁 に使う）。
    func isAvailable(_ game: GamePickerSelection, now: Date = .now) -> Bool {
        Self.targets.contains(game) && claimedDays[game.rawValue] != DayKey.string(for: now)
    }

    /// ゲームが終わったときに呼ぶ。きょうはじめてなら、ボーナスを渡す。
    /// - Returns: 渡したボーナス（kcal）。もう受け取っていれば 0。
    @discardableResult
    func claim(_ game: GamePickerSelection, now: Date = .now) -> Double {
        guard isAvailable(game, now: now) else { return 0 }
        claimedDays[game.rawValue] = DayKey.string(for: now)
        save()
        // 記録してからエネルギーを渡す（渡したあとで記録すると、間で終了されたとき二重にもらえてしまう）。
        // エネルギーの保存と一緒に、受け取った日も iCloud に送られる（EnergyStore の「iCloud との同期」を参照）
        EnergyStore.shared.grantDailyGameBonus(GameDailyBonusTuning.amount)
        return GameDailyBonusTuning.amount
    }

    // MARK: iCloud との同期（EnergyStore から呼ばれる）

    /// iCloud から届いた「受け取った日」を合わせる。ゲームごとに遅い日のほうを残す
    /// （同じ日に、iPhone と iPad で同じゲームのボーナスを2回もらわないように）。
    /// - Parameter force: true なら iCloud の記録で置きかえる（2択で「iCloud を もどす」を選んだとき）
    /// - Returns: 合わせた結果
    @discardableResult
    func merge(_ remote: [String: String], force: Bool) -> [String: String] {
        var merged = force ? [:] : claimedDays
        for (game, day) in remote {
            // "2026-10-15" の形なので、文字の大小で日付を比べられる
            if let local = merged[game], local >= day { continue }
            merged[game] = day
        }
        if merged != claimedDays {
            claimedDays = merged
            UserDefaults.standard.set(merged, forKey: Self.storageKey)
        }
        return merged
    }

    // MARK: リセット・保存

    /// 「さいしょから はじめる」で記録を消す（その日もまた、どのゲームでも受け取れる）。
    func reset() {
        claimedDays = [:]
        UserDefaults.standard.removeObject(forKey: Self.storageKey)
    }

    private func save() {
        UserDefaults.standard.set(claimedDays, forKey: Self.storageKey)
    }

    private static let storageKey = "gameDailyBonusDays"
}
