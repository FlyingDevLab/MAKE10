//
//  SharedFrame.swift
//  FDL-TenBlitz
//
//  Created by 空飛ぶ研究室(FlyingDevLab) on 2026/03/08.
//

// アプリ全画面で共通して使うレイアウトフレーム。
// ヘッダー（戻る・閉じる・設定）・コンテンツ領域・フッター（著作権表示）の3層構造を持ち、
// コンテンツだけを差し替えることで一貫したUIを維持したまま画面を切り替えられる。
// 設定パネルのオーバーレイもここで管理する。
//
// ★ アプリ全体の zIndex 階層表 ★
//   ZStack 内の重なり順はアプリ全体で以下の値に統一しています。
//   新しいオーバーレイを追加するときはこの表に収まる値を選んでください。
//     100 : 設定パネル（SettingsView。常に最前面）
//      50 : 紙吹雪（ConfettiView）
//      30 : フッター（著作権表示。シールが透けないように）
//      20 : シール（StickerBoardView）
//       0 : 通常コンテンツ
//
// ★ ジェネリクスとは？ ★
//   <Content: View> は「View に準拠した何かの型」を意味する型パラメータです。
//   SharedFrame は中身がタイトル画面でもゲーム画面でも構わないため、
//   「中身の型は呼び出し側が決める」という形で汎用化しています。
//   SwiftUI の VStack や ZStack も同じ仕組みで作られています。

import SwiftUI

// MARK: - SharedFrame

struct SharedFrame<Content: View>: View {

    // MARK: 設定項目（呼び出し側から渡すパラメータ）

    /// ヘッダー中央に表示するタイトル。nil のときはタイトルなし（空文字で表示）。
    var title:     String?       = nil

    /// 「戻る（chevron.left）」アクション。nil のときは戻るボタンを非表示にする。
    var onBack:    (() -> Void)? = nil

    /// 「閉じる（xmark）」アクション。nil のときは×ボタンを非表示にする。
    /// onBack と onDismiss は排他的に使う（両方セットされた場合は onBack が優先される）。
    var onDismiss: (() -> Void)? = nil

    /// 設定パネルに渡す GameViewModel。nil のときは設定パネル内のリセット項目が非表示になる。
    var gameViewModel:   GameViewModel? = nil

    /// 設定パネルが開閉したときにゲーム側のタイマーを制御するためのコールバック。
    var onSettingsOpen:  (() -> Void)?  = nil
    var onSettingsClose: (() -> Void)?  = nil

    // MARK: コンテンツ

    // ★ @ViewBuilder とは？ ★
    //   クロージャの中に複数の View を並べて書けるようにする属性です。
    //   呼び出し側は SharedFrame { ... } のトレイリングクロージャの中に
    //   if 分岐や複数のビューを自由に書けます（body と同じ書き心地になる）。

    /// 画面ごとのコンテンツをトレイリングクロージャで受け取る。
    @ViewBuilder let content: () -> Content

    // MARK: ローカル状態

    // ★ @State とは？ ★
    //   View 自身が持つ「画面の状態」を保存するための仕組みです。
    //   SwiftUI の View(struct) は描画のたびに作り直されますが、
    //   @State を付けた値だけは SwiftUI が裏で保持してくれるため、
    //   値が変わると自動的に画面が再描画されます。

    /// 設定パネルの表示状態。true になると SettingsView が zIndex(100) で最前面にオーバーレイされる。
    @State private var showSettings = false

    // MARK: body

    var body: some View {
        ZStack {
            // アプリ全体の背景色をセーフエリアを含めて塗りつぶす
            DS.bg.ignoresSafeArea()

            VStack(spacing: 0) {
                headerRow
                content()
                footerRow
            }

            // 設定パネルを最前面に重ねる（zIndex はヘッダの階層表を参照）
            if showSettings {
                SettingsView(isPresented: $showSettings, viewModel: gameViewModel)
                    .zIndex(100)
                    .transition(.opacity)
            }
        }
        // showSettings の変化をトリガーに設定パネルのフェードトランジションを適用する
        .animation(.easeInOut(duration: 0.25), value: showSettings)
        // 設定パネルの開閉に応じてゲームのタイマーを一時停止・再開する
        .onChange(of: showSettings) { _, isOpen in
            isOpen ? onSettingsOpen?() : onSettingsClose?()
        }
    }

    // MARK: ヘッダー

    /// ヘッダー行。左：戻る or 閉じるボタン（どちらも nil なら透明なスペーサー）、
    /// 中央：タイトル、右：設定ボタン（常に表示）。
    /// 左右ボタンを固定幅(52pt)にすることでタイトルが常に画面中央に配置される。
    private var headerRow: some View {
        HStack(spacing: 0) {
            Group {
                if let back = onBack {
                    // 戻るボタン（chevron.left）：onBack がある場合に表示する
                    Button {
                        SoundManager.shared.vibrate()
                        SoundManager.shared.playTap()
                        back()
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(DS.textPrimary.opacity(0.65))
                    }
                } else if let dismiss = onDismiss {
                    // 閉じるボタン（xmark）：onBack がなく onDismiss がある場合に表示する
                    Button {
                        SoundManager.shared.vibrate()
                        SoundManager.shared.playTap()
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 17, weight: .medium))
                            .foregroundStyle(DS.muted.opacity(0.75))
                    }
                } else {
                    // どちらも nil のとき：透明なスペーサーで右側の設定ボタンと幅を揃える
                    Color.clear
                }
            }
            .frame(width: 52, height: 44)

            // タイトルテキスト。lineLimit(1) でタイトルが長くても1行に収める
            Text(title ?? "")
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .foregroundStyle(DS.textPrimary)
                .lineLimit(1)
                .frame(maxWidth: .infinity)

            // 設定ボタン（常に右端に表示）。タップで SettingsView をオーバーレイとして表示する
            Button {
                SoundManager.shared.vibrate()
                SoundManager.shared.playTap()
                withAnimation { showSettings = true }
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 24, weight: .light))
                    .foregroundStyle(DS.muted.opacity(0.75))
            }
            .buttonStyle(.plain)
            .frame(width: 52, height: 44)
        }
        .padding(.horizontal, 8)
        .background(DS.bg)
    }

    // MARK: フッター

    /// 著作権表示をフッターに固定表示する。
    /// zIndex(30) で StickerBoardView(zIndex 20) より前面に配置し、
    /// background(DS.bg) を塗ることでシールがフッターを透過して見えるのを防ぐ。
    private var footerRow: some View {
        Text("© 空飛ぶ研究室 / Flying Dev Lab")
            // ⚠️ 変更注意: size 22 は意図的な設計判断。
            //   広告も外部リンクも持たないこのアプリにおいて、
            //   このフッターが唯一のブランド接点のため、あえて大きめに表示している。
            //   小さくしないこと。
            .font(.system(size: 22, weight: .medium, design: .rounded))
            .foregroundStyle(DS.muted.opacity(0.55))
            .frame(maxWidth: .infinity)
            .padding(.top, 28)
            .padding(.bottom, 0)
            .background(DS.bg)
            .zIndex(30)
    }
}
