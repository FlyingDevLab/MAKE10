//
//  AppSettings.swift
//  FDL-TenBlitz
//
//  Created by 空飛ぶ研究室(FlyingDevLab) on 2026/03/08.
//

// アプリ全体の設定（音・バイブなど）を一元管理するObservableシングルトン。
// UserDefaultsへの永続化もこのクラスが責務を持つ。

import SwiftUI

// MARK: - App Settings
// 音＆バイブを一括管理するシングルトン。

@Observable
final class AppSettings {

    // アプリ内どこからでも同一インスタンスにアクセスできるよう、シングルトンとして公開。
    static let shared = AppSettings()

    // サウンドのON/OFF状態。変更されるたびにUserDefaultsへ自動保存し、
    // 次回起動時も設定が引き継がれるようにする。
    var isSoundOn: Bool {
        didSet { UserDefaults.standard.set(isSoundOn, forKey: UDKey.isSoundOn) }
    }

    // 外部からの直接初期化を禁止し、shared経由のアクセスのみを強制する。
    // UserDefaultsに保存済みの値があればそれを復元し、なければデフォルトでONとする。
    private init() {
        self.isSoundOn = UserDefaults.standard.object(forKey: UDKey.isSoundOn) as? Bool ?? true
    }
}
