//
//  AppMigration.swift
//  FDL-TenBlitz
//
//  Created by 空飛ぶ研究室(FlyingDevLab) on 2026/10/01.
//
//  アプリを新しいバージョンに更新したとき、最初の起動で1回だけ行う処理をまとめる場所。
//  例: 記録の付け方を変えたので古い記録を消す、更新してくれた人にプレゼントを渡す、など。
//
//  役割分担:
//    - AppMigration（このファイル）: 「いつ・誰に」1回だけ実行するかの判断と、処理の中身
//    - FDL_TenBlitzApp              : 起動時に runIfNeeded() を呼ぶ
//    - MakeTenContentView           : プレゼントのお知らせカードを表示する
//
//  ★ 1回だけ実行する仕組み ★
//    処理を済ませたら UserDefaults に「済み」の印を保存し、次からは何もしない。
//    印はバージョンごとに別のキーにするので、将来のバージョンの処理も同じ形で足せる。
//    「さいしょからはじめる」（進捗リセット）でも印は消さない。消すとリセットのたびに
//    プレゼントがもらえてしまうため。
//
//  ★ 更新した人と新しくインストールした人の見分け方 ★
//    利用規約への同意（hasAgreedToTerms）は最初の起動で必ず済ませるので、
//    この処理の時点で同意済みなら「前のバージョンから使っている人」と判断できる。
//    新しくインストールした人はまだ同意していないので、プレゼントの対象にならない。

import Foundation

// MARK: - ⚙️ 調整パラメータ（ここだけ触ればOK）

enum AppMigrationTuning {
    /// 1.5.0 に更新してくれた人へのプレゼント（kcal）。
    static let updateGift150: Double = 10_000   // ← 変更可
    /// 1.6.0 に更新してくれた人へのプレゼント（kcal）。
    static let updateGift160: Double = 10_000   // ← 変更可
}

// MARK: - AppMigration

// case のない enum を名前空間として使う理由は ScoreBoard.swift を参照
enum AppMigration {

    /// 起動時に呼ぶ。まだ済ませていないバージョンの処理だけを実行する。
    static func runIfNeeded() {
        migrateTo150()
        migrateTo160()
    }

    // MARK: 1.5.0

    /// 1.5.0 への更新時の処理。
    ///   ・指令じゃんけんの最高記録をリセット（ノーミスのタイムだけを記録する方式に変えたため）
    ///   ・エネルギーをプレゼントし、タイトル画面でお知らせを出す
    private static func migrateTo150() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: UDKey.migration150Done) else { return }

        // hasAgreedToTerms の読み方は AppSettings.swift と同じ（未保存なら false＝新規インストール）
        let isUpdate = defaults.bool(forKey: UDKey.hasAgreedToTerms)
        if isUpdate {
            // ★ じゃんけんの記録を消す理由 ★
            //   1.4 以前はミスしてもクリアすれば記録になっていた。1.5 からはノーミスのタイムだけを
            //   記録するため、古い記録が残っているといつまでも抜けない記録になってしまう。
            //   ミスありかどうかは後から判別できないので、いったん全部消してそろえる。
            for key in [UDKey.jankenBestTimeEasy, UDKey.jankenBestTimeHard, UDKey.jankenBestTimeChallenge] {
                defaults.removeObject(forKey: key)
            }
            defaults.set(true, forKey: Self.jankenNotePendingKey)   // お知らせのカードで、記録を消したことを伝える
            grantUpdateGift(AppMigrationTuning.updateGift150)
        }
        // 新規インストールでも印は付ける（あとで同意しても、プレゼントの対象にしないため）
        defaults.set(true, forKey: UDKey.migration150Done)
    }

    // MARK: 1.6.0

    /// 1.6.0 への更新時の処理。
    ///   ・エネルギーをプレゼントし、タイトル画面でお知らせを出す
    ///   ・プライバシーポリシーをもう一度確かめて、同意してもらう
    ///
    /// ★ もう一度同意してもらう理由 ★（ユーザーと決めた「A」）
    ///   1.6.0 から、遊んだ記録を本人の iCloud に保存できるようになり、データの扱いが変わった。
    ///   保護者が新しいポリシーを確かめてから iCloud が動くよう、同意の印を外して同意画面をもう一度出す。
    ///   iCloud との同期は、同意したあとに始まる（CloudSyncManager.start を参照）。
    private static func migrateTo160() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: Self.migration160Done) else { return }
        // ⚠️ 順番に注意: 同意の印を外す「前」に、更新した人かどうかを見分ける（冒頭の「見分け方」を参照）
        if defaults.bool(forKey: UDKey.hasAgreedToTerms) {
            // お知らせのカードは、もう一度同意したあとのタイトル画面で出る（MakeTenContentView を参照）
            grantUpdateGift(AppMigrationTuning.updateGift160)
            // AppSettings を通して外す（画面が読む値と UserDefaults の両方がそろうように）
            AppSettings.shared.hasAgreedToTerms = false
        }
        defaults.set(true, forKey: Self.migration160Done)
    }

    /// 1.6.0 への更新時の処理を済ませたかの印（UserDefaults のキー）。
    private static let migration160Done = "migration_1_6_0_done"

    // MARK: プレゼント

    /// 更新してくれた人にエネルギーを渡し、タイトル画面でお知らせを出す予定にする。
    ///
    /// ★ 渡した量を足しておく理由 ★
    ///   1.4 から 1.6 へ一気に更新した人は、1.5.0 と 1.6.0 の両方のプレゼントを同じ起動でもらう。
    ///   お知らせのカードは1枚だけ出すので、カードに出す量を「まだ見せていない分の合計」にする。
    private static func grantUpdateGift(_ kcal: Double) {
        let defaults = UserDefaults.standard
        EnergyStore.shared.grantGift(kcal)
        defaults.set(defaults.double(forKey: Self.pendingGiftKcalKey) + kcal, forKey: Self.pendingGiftKcalKey)
        defaults.set(true, forKey: UDKey.updateGiftPending)
    }

    /// まだお知らせしていないプレゼントの合計（kcal）。UserDefaults のキー。
    private static let pendingGiftKcalKey = "updateGiftPendingKcal"

    // MARK: お知らせ

    /// お知らせのカードに出すプレゼントの量（kcal）。
    /// 1.5.x のときに受け取って、まだカードを見ていない人は合計が残っていないので、そのときは 1.5.0 の量を出す。
    static var pendingGiftKcal: Double {
        let total = UserDefaults.standard.double(forKey: pendingGiftKcalKey)
        return total > 0 ? total : AppMigrationTuning.updateGift150
    }

    /// お知らせのカードに「しれいじゃんけんの記録をリセットした」の一文を出すか。
    /// 1.5.0 の引っ越しで記録を消した人だけ。1.6.0 のプレゼントだけの人には出さない。
    static var showsJankenResetNote: Bool {
        UserDefaults.standard.bool(forKey: jankenNotePendingKey)
    }

    /// 「じゃんけんの記録を消した」とまだ伝えていない印（UserDefaults のキー）。
    private static let jankenNotePendingKey = "updateGiftJankenNotePending"

    /// アップデートのプレゼントのお知らせを、まだ見せていないか。
    static var hasPendingGiftNotice: Bool {
        UserDefaults.standard.bool(forKey: UDKey.updateGiftPending)
    }

    /// お知らせを見せ終わったときに呼ぶ。次の起動からは出さない。
    static func markGiftNoticeShown() {
        UserDefaults.standard.removeObject(forKey: UDKey.updateGiftPending)
        UserDefaults.standard.removeObject(forKey: pendingGiftKcalKey)
        UserDefaults.standard.removeObject(forKey: jankenNotePendingKey)
    }
}
