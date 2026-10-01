//
//  EnergyStore.swift
//  FDL-TenBlitz
//
//  Created by 空飛ぶ研究室(FlyingDevLab) on 2026/10/01.
//
//  ゲームで貯めて、シールのガチャ・ショップで使う「エネルギー（kcal）」を管理するシングルトン。
//  バナナ1本分の 100kcal でガチャが1回まわせる、という量の感覚で設計している。
//
//  役割分担:
//    - EnergyStore（このファイル）: エネルギーの残高・獲得・消費・永続化
//    - 各ゲームの ViewModel        : プレイ中の獲得（earn）とクリアボーナス（grantClearBonus）
//    - StickerGacha / StickerShop  : エネルギーを使ってシールを渡す（spend）
//    - StickerStore                : 手に入れたシールの保管
//
//  ★ エネルギーの増え方（体験の設計） ★
//    ・プレイ中: 正解ごとに earn() で少しずつ増える（ヘッダーの数字がその場で増える）
//    ・クリア後: grantClearBonus() でまとめてドサっと増える（結果画面で見せる）
//    どちらも呼んだ瞬間に残高へ加算・保存する。演出のために加算を遅らせると、
//    演出の途中でアプリが終了されたときにエネルギーが消えてしまうため。

import Foundation

// MARK: - ⚙️ 調整パラメータ（ここだけ触ればOK）
//
// ┌─────────────────────────────────────────────┐
// │  エネルギーの値段・おまけの数値を一箇所に集約。 │
// │  ゲームバランスを変えたいときはここだけ編集する。│
// └─────────────────────────────────────────────┘

enum EnergyTuning {
    /// クリアボーナスの基本単位（kcal）。1.4 以前の「ボーナスシール1枚」をこの量に置き換えた。
    /// クイズ全問正解・テンパズル全問正解・コインドロップのパーフェクトで1つ分、
    /// じゃんけんはクリア内容と難易度に応じて 1〜9 つ分を渡す。
    static let clearBonusUnit:  Double = 100    // ← 変更可

    /// ガチャ1回の値段（kcal）。バナナ1本分。
    static let gachaPrice:      Double = 100    // ← 変更可
    /// 10連ガチャでまわす回数。値段は gachaPrice × この回数になる。
    static let tenPullCount:    Int    = 10     // ← 変更可
    /// 10連ガチャのおまけ枚数。10連で合計 tenPullCount + この枚数 のシールが出る。
    static let tenPullBonus:    Int    = 1      // ← 変更可
    /// ショップでシールを1枚買う値段（kcal）。選べる分、ガチャより高い。
    static let shopPrice:       Double = 200    // ← 変更可
    /// ショップに毎日並ぶ「救済枠」の数。持っている枚数が少ないシールほど選ばれやすい。
    static let shopRescueSlots: Int    = 3      // ← 変更可
    /// ショップに毎日並ぶ「ランダム枠」の数。全シールから均等に選ぶ。
    static let shopRandomSlots: Int    = 7      // ← 変更可
    /// 救済枠の重みの強さ。重み = 1 ÷ (持っている枚数 + 1) ^ この値。
    /// 大きくするほど「持っていないシール」が強く優先される（0 にすると完全に均等）。
    /// 目安（249種類のうち2種類だけ未所持・ほかは5枚ずつの終盤で、未所持のシールが並ぶ日の割合）:
    ///   1 → 約10% / 2 → 約32% / 3 → 約74%
    /// 種類が多いので 1 だとほとんど救済にならず、3 だと同じシールが毎日並びやすい。
    static let rescueWeightExponent: Double = 2.0   // ← 変更可
}

// MARK: - EnergyStore

// @Observable / シングルトンの解説は AppSettings.swift 冒頭を参照
@Observable
final class EnergyStore {

    static let shared = EnergyStore()

    // MARK: 状態

    /// 残高（0.1kcal 単位の整数）。画面に出すときは balance を使う。
    ///
    /// ★ Double ではなく 0.1kcal 単位の Int で持っている理由 ★
    ///   Double は 1.8 のような小数を正確に表せず、足し算を重ねると
    ///   99.99999… のような誤差が生まれる。すると画面には「100.0kcal」と出ているのに
    ///   100kcal のガチャがまわせない、という不思議なことが起きてしまう。
    ///   獲得量は小数第1位までと決めているので、10倍した整数で持てば誤差が出ない。
    private(set) var balanceDeci: Int = 0

    /// 今回のプレイ中に earn() で増えた量（0.1kcal 単位）。beginSession() で 0 に戻る。
    private(set) var sessionEarnedDeci: Int = 0

    /// 今回のプレイで grantClearBonus() により増えた量（0.1kcal 単位）。beginSession() で 0 に戻る。
    private(set) var sessionClearBonusDeci: Int = 0

    // MARK: 表示用の値

    /// 残高（kcal）。
    var balance: Double { Double(balanceDeci) / 10 }

    /// 今回のプレイ中に増えた量（kcal）。結果画面の内訳表示に使う。
    var sessionEarned: Double { Double(sessionEarnedDeci) / 10 }

    /// 今回のクリアボーナス（kcal）。結果画面の内訳表示に使う。
    var sessionClearBonus: Double { Double(sessionClearBonusDeci) / 10 }

    // MARK: 初期化

    private init() { load() }

    // MARK: 獲得

    /// ゲーム開始時に呼ぶ。「今回の獲得量」を 0 に戻す（残高はそのまま）。
    func beginSession() {
        sessionEarnedDeci     = 0
        sessionClearBonusDeci = 0
    }

    /// プレイ中の獲得（正解1問ごとなど）。残高にすぐ加算して保存する。
    /// - Parameter kcal: 獲得量。小数第2位以下は四捨五入される。
    func earn(_ kcal: Double) {
        let deci = Self.toDeci(kcal)
        guard deci > 0 else { return }
        balanceDeci       += deci
        sessionEarnedDeci += deci
        save()
    }

    /// クリア後にまとめて渡すボーナス（旧ボーナスシールの置き換え・アーケード系のスコア換算）。
    /// 残高にすぐ加算して保存する。演出は結果画面が sessionClearBonus を見て行う。
    /// - Parameter kcal: 獲得量。小数第2位以下は四捨五入される。
    func grantClearBonus(_ kcal: Double) {
        let deci = Self.toDeci(kcal)
        guard deci > 0 else { return }
        balanceDeci           += deci
        sessionClearBonusDeci += deci
        save()
    }

    /// プレゼント（アップデートのお礼など）。残高にだけ加算し、「今回の獲得量」には含めない。
    /// ゲームの結果画面の内訳に混ざらないよう、earn / grantClearBonus とは分けている。
    func grantGift(_ kcal: Double) {
        let deci = Self.toDeci(kcal)
        guard deci > 0 else { return }
        balanceDeci += deci
        save()
    }

    // MARK: 消費

    /// 指定した量のエネルギーが足りているか。
    func canAfford(_ kcal: Double) -> Bool {
        balanceDeci >= Self.toDeci(kcal)
    }

    /// エネルギーを使う。足りなければ何もせず false を返す。
    /// - Returns: 使えたら true、足りなければ false
    // @discardableResult の解説は ScoreBoard.swift を参照
    @discardableResult
    func spend(_ kcal: Double) -> Bool {
        let deci = Self.toDeci(kcal)
        guard deci > 0, balanceDeci >= deci else { return false }
        balanceDeci -= deci
        save()
        return true
    }

    // MARK: リセット

    /// 進捗リセット時に残高と今回の獲得量をすべて 0 に戻す。
    func reset() {
        balanceDeci           = 0
        sessionEarnedDeci     = 0
        sessionClearBonusDeci = 0
        UserDefaults.standard.removeObject(forKey: UDKey.energyDeciKcal)
        UserDefaults.standard.removeObject(forKey: UDKey.totalCorrectAllTime)
    }

    // MARK: 表示用の書式

    /// kcal を「1,100.8」のような小数第1位までの文字列にする（単位は付けない）。
    /// 区切り記号（, と .）は端末の言語・地域設定に合わせて変わる。
    static func format(_ kcal: Double) -> String {
        kcal.formatted(.number.precision(.fractionLength(1)))
    }

    // MARK: 非公開

    /// kcal を 0.1kcal 単位の整数に変換する（四捨五入）。
    private static func toDeci(_ kcal: Double) -> Int {
        Int((kcal * 10).rounded())
    }

    // MARK: 保存／読み込み

    private func save() {
        UserDefaults.standard.set(balanceDeci, forKey: UDKey.energyDeciKcal)
    }

    /// 起動時に残高を復元する。
    ///
    /// ★ 1.4 以前のポイントの引き継ぎ ★
    ///   1.4 以前は「100pt 貯まると自動でシールが出る」仕組みで、端数のポイントが
    ///   totalCorrectAllTime（Double）に残っている。新しいキーがまだ無いときだけ
    ///   それを kcal として読み込み、新しいキーへ移して古いキーを消す。
    ///   こうすると移行は一度きりになり、2回目以降の起動では何も起きない。
    private func load() {
        let defaults = UserDefaults.standard
        if defaults.object(forKey: UDKey.energyDeciKcal) != nil {
            balanceDeci = defaults.integer(forKey: UDKey.energyDeciKcal)
        } else {
            balanceDeci = Self.toDeci(defaults.double(forKey: UDKey.totalCorrectAllTime))
            save()
            defaults.removeObject(forKey: UDKey.totalCorrectAllTime)
        }
    }
}
