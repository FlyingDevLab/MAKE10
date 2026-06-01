//
//  FDL_TenBlitzApp.swift
//  FDL-TenBlitz
//
//  Created by 空飛ぶ研究室(FlyingDevLab) on 2026/03/08.
//

// アプリのエントリーポイント。@mainによりここがアプリ起動時の最初の実行箇所になる。
// ルートViewとしてMakeTenContentViewを1つ表示するだけのシンプルな構成。
//
// ★ エントリーポイントとは？ ★
//   プログラムが「どこから動き始めるか」の出発点のことです。
//   C 言語では main() 関数がその役割を担いますが、
//   Swift + SwiftUI では @main を付けた struct がそれに相当します。
//   アプリを起動すると、iOS はまずここを呼び出します。
//
// ★ このファイルがシンプルな理由 ★
//   起動時の処理（画面構成・設定の読み込みなど）は
//   MakeTenContentView とその配下の各クラスに分散して書いてあります。
//   エントリーポイントは「最初のドアを開ける」だけに徹することで、
//   責任の分離が明確になります。

import SwiftUI

// ★ @main とは？ ★
//   この struct がアプリの起動点であることを Swift コンパイラに伝えるアノテーションです。
//   SwiftUI 以前は UIApplicationDelegate を実装した AppDelegate クラスが必要でしたが、
//   @main + App プロトコルの組み合わせにより、はるかにシンプルに書けるようになりました。
//
// ★ App プロトコルとは？ ★
//   SwiftUI が提供するアプリライフサイクル管理のためのプロトコルです。
//   準拠するには body プロパティ（some Scene を返す）を実装するだけでよく、
//   UIApplicationDelegate を書かずにアプリのライフサイクルを管理できます。

@main
struct FDL_TenBlitzApp: App {

    // ★ some Scene とは？ ★
    //   SwiftUI における「アプリの画面の枠組み」を表す型です。
    //   iOS では基本的に WindowGroup を1つ持つだけで十分です。
    //   some は「何らかの Scene 型」を返す不透明型の宣言で、
    //   実際の型（WindowGroup など）を呼び出し側に隠蔽できます。
    var body: some Scene {

        // ★ WindowGroup とは？ ★
        //   SwiftUI のアプリが持つ「ウィンドウのグループ」です。
        //   iOS では実質的に「1つのウィンドウ = アプリ画面全体」として機能します。
        //   iPadOS や macOS では複数ウィンドウに展開されることもありますが、
        //   iPhone では常に1画面として動作します。
        //
        //   {} の中に書いたビューがアプリ起動直後に表示される「最初の画面」になります。
        WindowGroup {
            // MakeTenContentView がアプリ全体の View 階層の起点（ルートView）。
            // ここから各ゲーム画面・設定画面などが枝分かれして表示される。
            MakeTenContentView()
        }
    }
}
