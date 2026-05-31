//
//  FDL_TenBlitzApp.swift
//  FDL-TenBlitz
//
//  Created by 空飛ぶ研究室(FlyingDevLab) on 2026/03/08.
//

// アプリのエントリーポイント。@mainによりここがアプリ起動時の最初の実行箇所になる。
// ルートViewとしてMakeTenContentViewを1つ表示するだけのシンプルな構成。

import SwiftUI

// @main：このstructがアプリのエントリーポイントであることをSwiftに伝えるアノテーション。
// Appプロトコルに準拠することで、UIApplicationDelegateなしにアプリライフサイクルを管理できる。
@main
struct FDL_TenBlitzApp: App {
    var body: some Scene {
        // WindowGroup：iOSでは1つのウィンドウとして機能する。
        // MakeTenContentViewをルートに設定し、アプリ全体のView階層の起点とする。
        WindowGroup {
            MakeTenContentView()
        }
    }
}
