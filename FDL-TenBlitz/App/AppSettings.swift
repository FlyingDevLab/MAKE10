//
//  AppSettings.swift
//  FDL-TenBlitz
//
//  Created by 空飛ぶ研究室(FlyingDevLab) on 2026/03/08.
//

// アプリ全体の設定（音・バイブなど）を一元管理するObservableシングルトン。
// UserDefaultsへの永続化もこのクラスが責務を持つ。
//
// ★ このファイルの役割 ★
//   「音をONにしているか」などのユーザー設定を保持するクラスです。
//   アプリ内のどの画面からでも AppSettings.shared と書くだけで
//   同じインスタンスにアクセスでき、設定を読み書きできます。
//
// ★ シングルトンとは？ ★
//   アプリ全体で「たった1つしか存在しないインスタンス」のことです。
//   設定値はアプリ内で1つに統一されていないと矛盾が生じるため、
//   シングルトンパターンが適しています。
//   static let shared = AppSettings() で唯一のインスタンスを作り、
//   private init() で外部からの new を禁止することで実現します。

import SwiftUI

// MARK: - App Settings
// 音＆バイブを一括管理するシングルトン。
//
// ★ @Observable とは？ ★
//   このマクロを付けると、クラスのプロパティが変化したとき
//   それを参照している SwiftUI のビューが自動で再描画されます。
//   たとえば設定画面でサウンドをOFFにした瞬間、
//   他の画面のスピーカーアイコンも自動で更新されます。

@Observable
final class AppSettings {

    // ★ static let とは？ ★
    //   インスタンスではなく「型そのもの」に属するプロパティです。
    //   AppSettings.shared と書くことでどこからでも同じインスタンスを参照できます。
    //   アプリ起動時に1度だけ生成され、以降は同じオブジェクトが使い回されます。

    /// アプリ内どこからでも同一インスタンスにアクセスできるよう、シングルトンとして公開。
    static let shared = AppSettings()

    // ★ didSet とは？ ★
    //   プロパティの値が変わった直後に自動で実行されるコードブロックです。
    //   isSoundOn が変更されるたびに UserDefaults への保存が走るため、
    //   「保存し忘れ」が構造的に起きません。

    /// サウンドのON/OFF状態。変更されるたびにUserDefaultsへ自動保存し、
    /// 次回起動時も設定が引き継がれるようにする。
    var isSoundOn: Bool {
        didSet { UserDefaults.standard.set(isSoundOn, forKey: UDKey.isSoundOn) }
    }

    // ★ private init() とは？ ★
    //   init() を private にすることで、このクラスを外部から
    //   AppSettings() と書いて直接インスタンス化できなくなります。
    //   必ず AppSettings.shared を経由させることで、
    //   シングルトンの「1つだけ」という約束が守られます。
    //
    // ★ as? Bool ?? true とは？ ★
    //   UserDefaults.object(forKey:) は Any? 型を返すため、
    //   as? Bool でオプショナルな Bool にキャスト（型変換）します。
    //   キャストに失敗（= 未保存 = 初回起動）した場合は
    //   ?? true によってデフォルト値の true（音ON）が使われます。

    /// 外部からの直接初期化を禁止し、shared経由のアクセスのみを強制する。
    /// UserDefaultsに保存済みの値があればそれを復元し、なければデフォルトでONとする。
    private init() {
        self.isSoundOn = UserDefaults.standard.object(forKey: UDKey.isSoundOn) as? Bool ?? true
    }
}
