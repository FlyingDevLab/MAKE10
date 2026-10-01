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
}

// MARK: - AppMigration

// case のない enum を名前空間として使う理由は ScoreBoard.swift を参照
enum AppMigration {

    /// 起動時に呼ぶ。まだ済ませていないバージョンの処理だけを実行する。
    static func runIfNeeded() {
        migrateTo150()
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
            EnergyStore.shared.grantGift(AppMigrationTuning.updateGift150)
            defaults.set(true, forKey: UDKey.updateGiftPending)
        }
        // 新規インストールでも印は付ける（あとで同意しても、プレゼントの対象にしないため）
        defaults.set(true, forKey: UDKey.migration150Done)
    }

    // MARK: お知らせ

    /// アップデートのプレゼントのお知らせを、まだ見せていないか。
    static var hasPendingGiftNotice: Bool {
        UserDefaults.standard.bool(forKey: UDKey.updateGiftPending)
    }

    /// お知らせを見せ終わったときに呼ぶ。次の起動からは出さない。
    static func markGiftNoticeShown() {
        UserDefaults.standard.removeObject(forKey: UDKey.updateGiftPending)
    }
}
