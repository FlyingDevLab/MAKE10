//
//  SharedFrame.swift
//  FDL-TenBlitz
//
//  Created by 空飛ぶ研究室(FlyingDevLab) on 2026/03/08.
//
//  全画面共通のフレーム。ヘッダー（戻る・閉じる・設定）、
//  コンテンツ領域、フッター（著作権表示）を提供する。

// アプリ全画面で共通して使うレイアウトフレーム。
// ヘッダー・コンテンツ・フッターの3層構造を持ち、コンテンツだけを差し替えることで
// 一貫したUIを維持したまま画面を切り替えられる。設定パネルのオーバーレイもここで管理する。

import SwiftUI

// ジェネリクスでコンテンツのView型を受け取る。
// 呼び出し側はSharedFrame { ... } のトレイリングクロージャでコンテンツを渡す
struct SharedFrame<Content: View>: View {

    // nilのときはヘッダー中央にタイトルなし（空文字で表示）
    var title:     String?       = nil

    // 「戻る（chevron.left）」アクション。nilのときは戻るボタンを非表示にする
    var onBack:    (() -> Void)? = nil

    // 「閉じる（xmark）」アクション。nilのときは×ボタンを非表示にする。
    // onBackとonDismissは排他的に使う（両方セットされた場合はonBackが優先される）
    var onDismiss: (() -> Void)? = nil

    // 設定パネルに渡すGameViewModel。nilのときは設定パネル内のリセット項目が非表示になる
    var gameViewModel:   GameViewModel? = nil

    // 設定パネルが開閉したときにタイマーを制御するためのコールバック
    var onSettingsOpen:  (() -> Void)?  = nil
    var onSettingsClose: (() -> Void)?  = nil

    // 画面ごとのコンテンツをトレイリングクロージャで受け取る
    @ViewBuilder let content: () -> Content

    // 設定パネルの表示状態。trueになるとSettingsViewがzIndex(100)で最前面にオーバーレイされる
    @State private var showSettings = false

    var body: some View {
        ZStack {
            // アプリ全体の背景色をセーフエリアを含めて塗りつぶす
            DS.bg.ignoresSafeArea()

            VStack(spacing: 0) {
                headerRow
                content()
                footerRow
            }

            // 設定パネルをZStackの最前面（zIndex 100）に重ねる。
            // zIndex(100)はシール(20)・紙吹雪(50)よりも高く、必ず最前面に来る
            if showSettings {
                SettingsView(isPresented: $showSettings, viewModel: gameViewModel)
                    .zIndex(100)
                    .transition(.opacity)
            }
        }
        // showSettingsの変化をトリガーに設定パネルのフェードトランジションを適用する
        .animation(.easeInOut(duration: 0.25), value: showSettings)
        // 設定パネルの開閉に応じてゲームのタイマーを一時停止・再開する
        .onChange(of: showSettings) { _, isOpen in
            isOpen ? onSettingsOpen?() : onSettingsClose?()
        }
    }

    // MARK: - Header

    // 左：戻る or 閉じるボタン（どちらもnilなら透明なスペーサー）
    // 中央：タイトル
    // 右：設定ボタン（常に表示）
    // 左右ボタンを固定幅(52pt)にすることでタイトルが常に画面中央に配置される
    private var headerRow: some View {
        HStack(spacing: 0) {
            Group {
                if let back = onBack {
                    // 戻るボタン（chevron.left）：onBackがある場合に表示する
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
                    // 閉じるボタン（xmark）：onBackがなくonDismissがある場合に表示する
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
                    // どちらもnilのとき：透明なスペーサーで右側の設定ボタンと幅を揃える
                    Color.clear
                }
            }
            .frame(width: 52, height: 44)

            // タイトルテキスト。lineLimit(1)でタイトルが長くても1行に収める
            Text(title ?? "")
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .foregroundStyle(DS.textPrimary)
                .lineLimit(1)
                .frame(maxWidth: .infinity)

            // 設定ボタン（常に右端に表示）。タップでSettingsViewをオーバーレイとして表示する
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

    // MARK: - Footer
    // zIndex(30) でシール（zIndex 20）より前面に出す。
    // background に DS.bg を塗ることでシールが透けて見えるのを防ぐ。

    // 著作権表示をフッターに固定表示する。
    // zIndex(30)でStickerBoardView(zIndex 20)より前面に配置し、
    // background(DS.bg)を塗ることでシールがフッターを透過して見えるのを防ぐ
    private var footerRow: some View {
        Text("© 空飛ぶ研究室 / Flying Dev Lab")
            .font(.system(size: 22, weight: .medium, design: .rounded))
            .foregroundStyle(DS.muted.opacity(0.55))
            .frame(maxWidth: .infinity)
            .padding(.top, 28)
            .padding(.bottom, 0)
            .background(DS.bg)
            .zIndex(30)
    }
}
