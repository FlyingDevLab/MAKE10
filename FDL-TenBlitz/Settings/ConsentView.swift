//
//  ConsentView.swift
//  FDL-TenBlitz
//
//  Created by 空飛ぶ研究室(FlyingDevLab) on 2026/03/08.
//

// 初回起動時に表示する同意画面と、アプリ内ポリシー閲覧シートを定義するファイル。
// 外部リンク・mailto・データ送信を一切使わないという方針をUIレベルで実現している。

import SwiftUI

// MARK: - Consent View
// 初回起動時のみ表示する免責事項・プライバシーポリシー同意画面。
// ポリシー本文はアプリ内モーダルで表示し、外部リンクは一切使用しない。
// チェックボックスにチェックを入れるまで「同意してはじめる」ボタンは無効。

struct ConsentView: View {

    // 同意ボタンが押されたときの処理を呼び出し元から受け取る。
    // ConsentViewは「同意の取得」に専念し、その後の画面遷移は親に委ねる設計。
    let onAgree: () -> Void

    // チェックボックスのON/OFF状態。同意ボタンの活性化条件にもなる
    @State private var isChecked     = false

    // ポリシーシートの表示フラグ。trueになるとPolicyViewがsheetで開く
    @State private var showPolicy    = false

    var body: some View {
        ZStack {
            DS.bg.ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                // ロゴ＆タイトル
                VStack(spacing: 8) {
                    Text("☁️")
                        .font(.system(size: 56))
                    Text("consent_app_name")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundStyle(DS.primary)
                    Text("consent_developer_name")
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundStyle(DS.muted)
                }
                .padding(.bottom, 32)

                // 本文カード
                VStack(alignment: .leading, spacing: 16) {

                    // 同意を求める説明文。ローカライズキーで多言語対応済み
                    Text("consent_body")
                        .font(.system(size: 15, weight: .regular, design: .rounded))
                        .foregroundStyle(DS.textBody)
                        .lineSpacing(4)
                        .fixedSize(horizontal: false, vertical: true)

                    // ポリシーをアプリ内で開くボタン
                    // Safariや外部ブラウザへは遷移させず、PolicyViewをsheetで表示する
                    Button {
                        showPolicy = true
                    } label: {
                        HStack(spacing: 6) {
                            Text("consent_policy_link")
                                .font(.system(size: 14, weight: .semibold, design: .rounded))
                                .foregroundStyle(DS.primary)
                            Image(systemName: "doc.text")
                                .font(.system(size: 13))
                                .foregroundStyle(DS.primary)
                        }
                    }
                    .buttonStyle(.plain)

                    Divider()

                    // チェックボックス
                    // タップでisCheckedをトグルし、スプリングアニメーションでチェックマークを表示する
                    Button {
                        withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) {
                            isChecked.toggle()
                        }
                    } label: {
                        HStack(alignment: .top, spacing: 12) {
                            ZStack {
                                // チェック状態に応じて枠線色・背景色を切り替えるカスタムチェックボックス
                                RoundedRectangle(cornerRadius: DS.smallRadius)
                                    .strokeBorder(
                                        isChecked ? DS.primary : DS.muted.opacity(0.5),
                                        lineWidth: 2
                                    )
                                    .frame(width: 24, height: 24)
                                    .background(
                                        RoundedRectangle(cornerRadius: DS.smallRadius)
                                            .fill(isChecked ? DS.primary : Color.clear)
                                    )

                                // チェック済みのときだけチェックマークアイコンを表示する
                                // .transition修飾子でスケール＋フェードの組み合わせアニメーションを付与
                                if isChecked {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 13, weight: .bold))
                                        .foregroundStyle(.white)
                                        .transition(.scale.combined(with: .opacity))
                                }
                            }
                            .frame(width: 24, height: 24)

                            Text("consent_checkbox_label")
                                .font(.system(size: 14, weight: .medium, design: .rounded))
                                .foregroundStyle(DS.textBody)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .buttonStyle(.plain)
                }
                .padding(24)
                .background(
                    RoundedRectangle(cornerRadius: DS.cardRadius)
                        .fill(DS.card)
                        .shadow(color: .black.opacity(0.07), radius: 14, x: 0, y: 5)
                )
                .padding(.horizontal, 28)

                Spacer()

                // 同意ボタン（チェック前はグレーアウト）
                // .disabled(!isChecked) でタップを無効化しつつ、
                // 背景色・シャドウもisCheckedに連動させて視覚的にも無効状態を伝える
                Button(action: onAgree) {
                    Text("consent_agree_button")
                        .font(.system(size: 20, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 18)
                        .background(
                            RoundedRectangle(cornerRadius: DS.btnRadius)
                                .fill(isChecked ? DS.primary : DS.muted.opacity(0.35))
                                .shadow(
                                    color: isChecked ? DS.primary.opacity(0.35) : .clear,
                                    radius: 8, x: 0, y: 4
                                )
                        )
                }
                .buttonStyle(.plain)
                .disabled(!isChecked)
                .animation(.easeInOut(duration: 0.2), value: isChecked)
                .padding(.horizontal, 28)
                .padding(.bottom, 52)
            }
        }
        // ポリシーリンクのタップでPolicyViewをシートとして表示する
        .sheet(isPresented: $showPolicy) {
            PolicyView()
        }
    }
}

// MARK: - Policy View
// プライバシーポリシー・免責事項をアプリ内で表示するシート。
// 外部リンク・mailto・データ送信を一切使わない。
// お問い合わせは公式サイトURLをクリップボードにコピーする方式のみ。

struct PolicyView: View {
    @Environment(\.dismiss) private var dismiss

    // コピーボタン押下後のフィードバック表示フラグ。2秒後に自動でfalseに戻る
    @State private var didCopy = false

    // お問い合わせURLはローカライズキーから取得し、コードに直接埋め込まない
    private let contactURL = String(localized: "policy_contact_url")

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {

                    // ポリシー本文
                    // 長文になりうるため fixedSize で縦方向に自動伸長させる
                    Text("policy_full_text")
                        .font(.system(size: 14, weight: .regular, design: .rounded))
                        .foregroundStyle(DS.textDark)
                        .lineSpacing(5)
                        .fixedSize(horizontal: false, vertical: true)

                    // お問い合わせカード（コピーのみ）
                    // リンクではなくURLのコピー機能だけを提供することで、
                    // App Storeのガイドラインに準拠した外部リンクなし設計を維持する
                    VStack(alignment: .leading, spacing: 12) {
                        Text("policy_contact_heading")
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                            .foregroundStyle(DS.textDark)

                        Text("policy_contact_description")
                            .font(.system(size: 13, weight: .regular, design: .rounded))
                            .foregroundStyle(DS.muted)
                            .lineSpacing(4)

                        // URL表示 + コピーボタン
                        HStack(spacing: 10) {
                            // URLを読み取り専用のテキストとして表示する（タップ不可）
                            Text(contactURL)
                                .font(.system(size: 14, weight: .medium, design: .monospaced))
                                .foregroundStyle(DS.textDark)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)

                            Spacer()

                            // コピーボタン。押下でURLをクリップボードに書き込み、
                            // 2秒間だけ「コピー完了」状態のアイコン＆テキストに切り替える
                            Button {
                                UIPasteboard.general.string = contactURL
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                    didCopy = true
                                }
                                // 2秒後に自動でコピー前の表示に戻す
                                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                    withAnimation { didCopy = false }
                                }
                            } label: {
                                HStack(spacing: 4) {
                                    // didCopyの状態でアイコンをコピー前後で切り替える
                                    Image(systemName: didCopy ? "checkmark" : "doc.on.doc")
                                        .font(.system(size: 12, weight: .semibold))
                                    if didCopy {
                                        Text("policy_copied_label")
                                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                                    } else {
                                        Text("policy_copy_button")
                                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                                    }
                                }
                                // コピー完了時は緑、通常時はアクセントカラーで色を切り替える
                                .foregroundStyle(didCopy ? .green : DS.primary)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 7)
                                .background(
                                    RoundedRectangle(cornerRadius: DS.iconRadius)
                                        .fill(didCopy ? Color.green.opacity(0.1) : DS.primary.opacity(0.1))
                                )
                            }
                            .buttonStyle(.plain)
                            .animation(.easeInOut(duration: 0.2), value: didCopy)
                        }
                        .padding(14)
                        .background(
                            RoundedRectangle(cornerRadius: DS.inputRadius)
                                .fill(DS.inputBg)
                        )
                    }
                    .padding(.top, 28)
                }
                .padding(24)
            }
            .navigationTitle("policy_sheet_title")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // 閉じるボタン。シートをdismissするだけで副作用はない
                ToolbarItem(placement: .confirmationAction) {
                    Button("policy_close_button") { dismiss() }
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundStyle(DS.primary)
                }
            }
            .background(DS.bg.ignoresSafeArea())
        }
    }
}
