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
//    ・プレイ中: 正解ごとに earn() で +1 ずつ増える（ヘッダーの数字がその場で増える）
//    ・クリア後: grantClearBonus() で「正解の数 × 倍率」がドサっと増える（結果画面で見せる）
//    量は下の EnergyRewards の表でまとめて調整できる。
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

// MARK: - ⚙️ もらえるエネルギーの表（ゲームごと・ここだけ触ればOK）
//
// ┌──────────────────────────────────────────────────────────┐
// │  どのゲームで、いつ、どれだけエネルギーが増えるかを一箇所に集約。  │
// │  ゲームバランスを変えたいときはここだけ編集する。                  │
// └──────────────────────────────────────────────────────────┘
//
// ★ 増え方のルール（全ゲーム共通） ★
//   ① プレイ中: 正解（もぐらを叩く・チーズを取る など）のたびに perCorrect（+1）ずつ増える。
//      ヘッダーの数字がその場で増えていくのを見せるため。
//   ② クリア後: 「正解の数 × ゲームごとの倍率」をクリアボーナスとしてまとめて渡す。
//      難しいゲーム・モードほど倍率を高くしている（難易度の予想順は下の各項目のコメント）。
//   ③ 全問正解などの特別な達成には perfectBonus（+100）を上乗せする。
//   クリアボーナスは小数になったら四捨五入する（画面には整数しか出さないため）。

enum EnergyRewards {
    /// 正解1回ごとにプレイ中に増える量（kcal）。全ゲーム共通。
    static let perCorrect:   Double = 1      // ← 変更可
    /// 全問正解・パーフェクトなど、特別な達成のボーナス（kcal）。
    static let perfectBonus: Double = 100    // ← 変更可

    /// もぐら叩き（難易度の予想: いちばんやさしい）。クリアボーナス = 叩いた数 × この倍率。
    static let whackAMoleBonusRate: Double = 0.5   // ← 変更可

    /// 指令じゃんけん。クリアボーナス = 正解の数 × 難易度ごとの倍率。ノーミスで perfectBonus。
    static let jankenBonusRateEasy:      Double = 1    // ← 変更可（予想: やさしい）
    static let jankenBonusRateHard:      Double = 3    // ← 変更可（予想: ふつう。「負けて」は頭の切り替えが必要）
    static let jankenBonusRateChallenge: Double = 4    // ← 変更可（予想: むずかしい。30問）

    /// 絵文字クイズ。クリアボーナス = 正解の数 × モードごとの倍率。全問正解で perfectBonus。
    static let quizBonusRateBasic: Double = 1.5   // ← 変更可（ふつう）
    static let quizBonusRateHard:  Double = 2     // ← 変更可（むずかしい）

    /// コインドロップ。クリアボーナス = 作った$1の数 × この倍率。$10達成で perfectBonus。
    static let coinDropBonusRate: Double = 2      // ← 変更可

    /// 迷路。クリアボーナス = 取ったチーズの数 × この倍率（チーズは数が少ないので高め）。
    static let mazeBonusRate: Double = 3          // ← 変更可

    /// ピンボール。この点数ごとに「正解1回」と数える（プレイ中に +1）。
    static let pinballPointsPerCorrect: Int = 1000 // ← 変更可
    /// ピンボールのクリアボーナス = 正解の数（点数 ÷ pinballPointsPerCorrect）× この倍率。
    static let pinballBonusRate: Double = 0.5     // ← 変更可

    /// MAKE10。クリアボーナス = 正解の数 × モードごとの倍率。
    static let make10BonusRateNormal: Double = 1  // ← 変更可（30びょう）
    static let make10BonusRateBlitz:  Double = 6  // ← 変更可（10びょう）

    /// 四則テンパズル。クリアボーナス = 正解の数 × モードごとの倍率。全問正解で perfectBonus。
    static let tenPuzzleBonusRateA: Double = 2    // ← 変更可（かんたん / ふつう）
    static let tenPuzzleBonusRateB: Double = 4    // ← 変更可（むずかしい）
    static let tenPuzzleBonusRateC: Double = 6    // ← 変更可（チャレンジ）
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
    ///   Double は 0.1 のような小数を正確に表せず、足し算を重ねると 99.99999… のような
    ///   誤差が生まれる。いまの獲得量はすべて整数だが、1.4 以前から引き継いだポイントには
    ///   端数（例: 57.4）があるため、その端数を誤差なく持てるよう 10倍した整数で保存している。
    ///   （画面には整数しか出さない。format を参照）
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

    /// クリア後にまとめて渡すボーナス（正解の数 × 倍率、全問正解ボーナスなど）。
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

    /// kcal を「1,100」のような整数の文字列にする（単位は付けない）。
    /// 区切り記号（,）は端末の言語・地域設定に合わせて変わる。
    ///
    /// ★ 小数点を表示しない理由 ★
    ///   子どもには小数の概念が難しいため。獲得量はすべて整数にしているが、
    ///   1.4 以前から引き継いだ端数（例: 57.4）が残っている場合があるので、切り捨てて表示する。
    ///   切り捨てなら「表示されている数 ≦ 本当の残高」になるので、表示どおりの値段のものは必ず買える。
    static func format(_ kcal: Double) -> String {
        kcal.rounded(.down).formatted(.number.precision(.fractionLength(0)))
    }

    /// 足りない量を整数で表示する文字列。端数があれば切り上げる（「あと 0」と出さないため）。
    static func formatShortage(_ kcal: Double) -> String {
        max(1, kcal.rounded(.up)).formatted(.number.precision(.fractionLength(0)))
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
