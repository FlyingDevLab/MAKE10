//
//  DailyBonus.swift
//  FDL-TenBlitz
//
//  Created by 空飛ぶ研究室(FlyingDevLab) on 2026/10/01.
//
//  毎日のログインボーナスと、初めてインストールした日の「はじめまして」プレゼントを管理する。
//  その日に初めてアプリを開いたとき（0時区切り）に1回だけエネルギーを渡し、お知らせカードを出す。
//
//  役割分担:
//    - DailyBonus（このファイル）: いつ・いくら渡すかの判断、エネルギーの付与、お知らせの記録
//    - EnergyStore              : エネルギーの加算（grantGift）
//    - MakeTenContentView       : お知らせカードを、タイトル画面にいるときに順番に出す
//
//  ★ 連続ボーナスの考え方（子どもに「毎日開かないと損」と感じさせないために） ★
//    前の日にも開いていれば少し多め（150kcal）、そうでなければいつもの量（100kcal）。
//    連続の日数は数えず、画面にも出さない。1日空いても「へった」とは見せず、
//    カードの言葉を「きてくれて ありがとう」に変えるだけにしている。
//
//  ★ エネルギーを渡すタイミングとカードを出すタイミングを分けている理由 ★
//    ゲームの途中で日付が変わってアプリに戻ってきた場合も、エネルギーはすぐ渡して保存する。
//    ただしカードはタイトル画面に戻るまで出さない（MAKE10 のタイマーなどを邪魔しないため）。
//    カードを見る前にアプリが終了されても、次に開いたときにカードが出る。

import Foundation

// MARK: - ⚙️ 調整パラメータ（ここだけ触ればOK）

enum DailyBonusTuning {
    /// その日に初めて開いたときのボーナス（kcal）。バナナ1本分＝ガチャ1回分。
    static let loginBonus:   Double = 100    // ← 変更可
    /// 前の日にも開いていたときのボーナス（kcal）。
    static let streakBonus:  Double = 150    // ← 変更可
    /// 初めてインストールした日の「はじめまして」プレゼント（kcal）。その日はログインボーナスの代わりになる。
    static let welcomeGift:  Double = 1_000  // ← 変更可
}

// MARK: - DailyBonus

// case のない enum を名前空間として使う理由は ScoreBoard.swift を参照
enum DailyBonus {

    /// お知らせカードに出す内容。
    enum Notice: Equatable {
        /// 初めてインストールした日のプレゼント。
        case welcome
        /// 毎日のログインボーナス。isStreak は前の日にも開いていたか（カードの言葉を変える）。
        case login(kcal: Double, isStreak: Bool)
    }

    // MARK: 起動時の準備

    /// アプリの起動時（利用規約に同意する前）に呼ぶ。新しくインストールした人かどうかを記録する。
    ///
    /// ★ 起動時に判定する理由 ★
    ///   ログインボーナスを渡すのは利用規約に同意した後なので、その時点では
    ///   「前から使っている人」と「いま同意したばかりの人」の区別がつかない。
    ///   同意前の起動時なら、まだ同意していない＝新しくインストールした人だと分かる。
    static func prepareAtLaunch() {
        let defaults = UserDefaults.standard
        let isFirstEver = defaults.string(forKey: UDKey.dailyBonusLastDay) == nil
                       && !defaults.bool(forKey: UDKey.hasAgreedToTerms)
        if isFirstEver {
            defaults.set(true, forKey: UDKey.welcomeGiftPending)
        }
    }

    // MARK: その日の受け取り

    /// アプリを開いたとき・アプリに戻ってきたときに呼ぶ。その日にまだ受け取っていなければ
    /// エネルギーを渡し、お知らせを記録する。利用規約に同意していなければ何もしない。
    static func checkIn(now: Date = .now) {
        let defaults = UserDefaults.standard
        guard defaults.bool(forKey: UDKey.hasAgreedToTerms) else { return }

        let today = DayKey.string(for: now)

        // 初めてインストールした日は「はじめまして」を渡し、その日のログインボーナスの代わりにする
        if defaults.bool(forKey: UDKey.welcomeGiftPending) {
            EnergyStore.shared.grantGift(DailyBonusTuning.welcomeGift)
            defaults.removeObject(forKey: UDKey.welcomeGiftPending)
            defaults.set(true, forKey: UDKey.welcomeNoticePending)
            defaults.set(today, forKey: UDKey.dailyBonusLastDay)
            return
        }

        let lastDay = defaults.string(forKey: UDKey.dailyBonusLastDay)
        guard lastDay != today else { return }

        let isStreak = lastDay == DayKey.previousDay(of: now)
        let kcal = isStreak ? DailyBonusTuning.streakBonus : DailyBonusTuning.loginBonus
        EnergyStore.shared.grantGift(kcal)
        defaults.set(today, forKey: UDKey.dailyBonusLastDay)
        defaults.set(kcal, forKey: UDKey.loginNoticeKcal)
        defaults.set(isStreak, forKey: UDKey.loginNoticeIsStreak)
    }

    // MARK: お知らせ

    /// まだ見せていないお知らせ（出す順）。
    static var pendingNotices: [Notice] {
        let defaults = UserDefaults.standard
        var notices: [Notice] = []
        if defaults.bool(forKey: UDKey.welcomeNoticePending) {
            notices.append(.welcome)
        }
        let kcal = defaults.double(forKey: UDKey.loginNoticeKcal)
        if kcal > 0 {
            notices.append(.login(kcal: kcal, isStreak: defaults.bool(forKey: UDKey.loginNoticeIsStreak)))
        }
        return notices
    }

    /// お知らせを見せ終わったときに呼ぶ。
    static func markShown(_ notice: Notice) {
        let defaults = UserDefaults.standard
        switch notice {
        case .welcome:
            defaults.removeObject(forKey: UDKey.welcomeNoticePending)
        case .login:
            defaults.removeObject(forKey: UDKey.loginNoticeKcal)
            defaults.removeObject(forKey: UDKey.loginNoticeIsStreak)
        }
    }
}
