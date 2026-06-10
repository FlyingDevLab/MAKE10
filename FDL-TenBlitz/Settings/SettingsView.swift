//
//  SettingsView.swift
//  FDL-TenBlitz
//
//  Created by 空飛ぶ研究室(FlyingDevLab) on 2026/03/08.
//

// SharedFrame から呼ばれるオーバーレイ型の設定パネルと、リセット確認ダイアログを定義するファイル。
// 音・ハプティクスのトグル、ハイスコア/進捗リセット、プライバシーポリシー表示を提供する。
// 設定パネルは ZStack で背景を暗くしてダイアログ風に表示し、背景タップで閉じられる。
//
// ★ このファイルの構成 ★
//   SettingsView     … 設定パネル本体（SharedFrame が zIndex 100 でオーバーレイ表示する）
//   ResetConfirmView … リセット操作の最終確認ダイアログ
//   ※ リセット対象を表す ResetTarget enum は MakeTenModels.swift に定義されている
//
// 役割分担:
//   viewModel が nil の場合（クイズ画面から開いた場合等）はリセット項目を非表示にする。
//   実際のリセット処理は GameViewModel 側（resetHighScore / resetProgress）が担い、
//   この画面は「確認を取って呼ぶ」ことに専念する。

import SwiftUI

// MARK: - SettingsView

struct SettingsView: View {

    // MARK: 依存（親・共有オブジェクト）

    // ★ @Binding とは？ ★
    //   親View が持つ @State を「共有」して読み書きするための仕組みです。
    //   ここでは SharedFrame の showSettings を受け取っており、
    //   この画面側で isPresented = false にすると親の showSettings も false になり、
    //   パネルが閉じます。値のコピーではなく「同じ変数への参照」だと考えると理解しやすいです。

    /// 設定パネルの表示状態を親View（SharedFrame）と共有する。
    @Binding var isPresented: Bool

    /// MAKE10 の GameViewModel。nil のとき（クイズ画面からの呼び出しなど）はリセット項目を非表示にする。
    var viewModel: GameViewModel? = nil

    // ★ @Bindable とは？ ★
    //   @Observable なクラス（ここでは AppSettings）のプロパティから
    //   $settings.isSoundOn のような Binding を取り出せるようにする仕組みです（iOS 17〜）。
    //   これにより Toggle に直接バインドでき、スイッチを切り替えた瞬間に
    //   AppSettings の didSet が走って UserDefaults へ自動保存されます。
    //   （@Observable の解説は AppSettings.swift 冒頭を参照）

    /// AppSettings.shared へのバインディング。トグルの変更が即座に UserDefaults に反映される。
    @Bindable var settings = AppSettings.shared

    // MARK: ローカル状態

    /// リセット確認ダイアログの対象。nil のときはダイアログ非表示、セットされると確認ダイアログが出現する。
    @State private var confirmTarget: ResetTarget? = nil

    /// ポリシーシートの表示フラグ。
    @State private var showPolicy:    Bool         = false

    // MARK: 表示条件

    /// Blitzモードかつハイスコア解放済みのときのみハイスコアリセットボタンを表示する。
    private var showHighScoreReset: Bool {
        viewModel?.isHighScoreUnlocked ?? false
    }

    /// Blitzモード解放済みのときのみ進捗リセットボタンを表示する。
    private var showProgressReset: Bool {
        viewModel?.isBlitzUnlocked ?? false
    }

    // MARK: body

    var body: some View {
        ZStack {
            // 背景の暗幕。タップで設定パネルを閉じる
            Color.black.opacity(0.22)   // ← 変更可（暗幕の濃さ 0.0〜1.0）
                .ignoresSafeArea()
                .onTapGesture { isPresented = false }

            VStack(spacing: 24) {
                Text("settings_title")
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .foregroundStyle(DS.primary)

                // ── 音＆バイブ トグル ──────────────────────
                // AppSettings.shared に直接バインドし、変更が UserDefaults に即時保存される
                VStack(spacing: 0) {
                    settingRow(
                        icon:  "speaker.wave.2.fill",
                        label: "settings_sound_haptic_label",
                        isOn:  $settings.isSoundOn
                    )
                }
                .background(
                    RoundedRectangle(cornerRadius: DS.sectionRadius)
                        .fill(DS.settingsBg)
                )

                // ── リセットボタン（viewModel がある場合のみ）──
                // 解放状況に応じてハイスコアリセット・進捗リセットを条件付きで表示する
                if showHighScoreReset || showProgressReset {
                    VStack(spacing: 10) {
                        if showHighScoreReset {
                            // タップすると confirmTarget を .highScore にセットして確認ダイアログを出す
                            resetButton(
                                icon:  "trophy",
                                label: "settings_reset_high_score",
                                color: DS.gold
                            ) { confirmTarget = .highScore }
                        }
                        if showProgressReset {
                            // タップすると confirmTarget を .progress にセットして確認ダイアログを出す
                            resetButton(
                                icon:  "arrow.counterclockwise",
                                label: "settings_reset_progress",
                                color: DS.gaugeWarn
                            ) { confirmTarget = .progress }
                        }
                    }
                }

                // ── プライバシーポリシー ────────────────────
                // Safariや外部リンクは使わず、PolicyView を sheet で表示するアプリ内閲覧方式
                // （外部リンクを使わない理由は ConsentView.swift 冒頭を参照）
                Button { showPolicy = true } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "doc.text")
                            .font(.system(size: 15))
                            .foregroundStyle(DS.muted)
                        Text("settings_policy_button")
                            .font(.system(size: 15, weight: .medium, design: .rounded))
                            .foregroundStyle(DS.muted)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12))
                            .foregroundStyle(DS.muted.opacity(0.5))
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 13)
                    .background(
                        RoundedRectangle(cornerRadius: DS.chipRadius)
                            .fill(DS.muted.opacity(0.07))
                    )
                }
                .buttonStyle(.plain)

                // ── 閉じるボタン ────────────────────────────
                Button { isPresented = false } label: {
                    Text("settings_close_button")
                        .font(.system(size: 18, weight: .semibold, design: .rounded))
                        .foregroundStyle(DS.muted)
                        .padding(.horizontal, 36)
                        .padding(.vertical, 11)
                        .background(Capsule().fill(Color.black.opacity(0.05)))
                }
                .buttonStyle(.plain)
            }
            .padding(32)
            .background(
                RoundedRectangle(cornerRadius: DS.dialogRadius)
                    .fill(DS.card)
                    .shadow(color: .black.opacity(0.10), radius: 24, x: 0, y: 8)
            )
            .padding(.horizontal, 36)

            // ── リセット確認ダイアログ ──────────────────────
            // confirmTarget がセットされたときだけ ZStack 上に重なって表示する。
            // 確認後は onConfirm で ViewModel のリセットメソッドを呼び、confirmTarget を nil に戻す
            if let target = confirmTarget {
                ResetConfirmView(target: target) {
                    switch target {
                    case .highScore: viewModel?.resetHighScore()
                    case .progress:  viewModel?.resetProgress()
                    }
                    confirmTarget = nil  // ダイアログを閉じる
                } onCancel: {
                    confirmTarget = nil  // キャンセル時もダイアログを閉じる
                }
            }
        }
        .sheet(isPresented: $showPolicy) {
            PolicyView()
        }
    }

    // MARK: サブビュー生成ヘルパー

    /// 設定行を生成するヘルパー。アイコン・ラベル・トグルを横並びにしたレイアウトを返す。
    /// 現在は音＆バイブのみだが、設定項目が増えた場合も同じメソッドで追加できる。
    private func settingRow(icon: String, label: LocalizedStringKey, isOn: Binding<Bool>) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundStyle(DS.primary)
                .frame(width: 28)
            Text(label)
                .font(.system(size: 20, weight: .medium, design: .rounded))
                .foregroundStyle(DS.textBody)
            Spacer()
            Toggle("", isOn: isOn).labelsHidden().tint(DS.primary)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
    }

    /// リセットボタンを生成するヘルパー。アイコン・ラベル・色を引数で受け取り、
    /// ハイスコアと進捗の2種類のボタンを同じスタイルで生成する。
    private func resetButton(
        icon: String, label: LocalizedStringKey, color: Color, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 15))
                    .foregroundStyle(color)
                Text(label)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(color)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12))
                    .foregroundStyle(color.opacity(0.5))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 13)
            .background(
                RoundedRectangle(cornerRadius: DS.chipRadius)
                    .fill(color.opacity(0.08))
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - ResetConfirmView

/// リセット操作の最終確認を求めるダイアログ。
/// target に応じてタイトルと本文を切り替え、「実行」と「キャンセル」の2択を提供する。
/// 誤操作を防ぐため、リセットボタンを直接実行するのではなくこのダイアログを経由する設計にしている。
struct ResetConfirmView: View {

    // MARK: 設定項目（呼び出し側から渡すパラメータ）

    /// ハイスコアリセットか進捗リセットかを識別する。
    let target:    ResetTarget
    /// 「実行」タップ時のコールバック。
    let onConfirm: () -> Void
    /// 「キャンセル」タップ時のコールバック。
    let onCancel:  () -> Void

    // MARK: 表示文言

    /// target に応じて確認ダイアログのタイトルを切り替える。
    private var titleKey: LocalizedStringKey {
        target == .highScore ? "reset_confirm_high_score_title" : "reset_confirm_progress_title"
    }

    /// target に応じて確認ダイアログの本文を切り替える。
    private var bodyKey: LocalizedStringKey {
        target == .highScore ? "reset_confirm_high_score_body" : "reset_confirm_progress_body"
    }

    // MARK: body

    var body: some View {
        ZStack {
            // 背景の暗幕。設定パネル(0.22)より暗くして「さらに前面にある」ことを視覚的に伝える
            Color.black.opacity(0.30).ignoresSafeArea()   // ← 変更可（暗幕の濃さ 0.0〜1.0）

            VStack(spacing: 20) {
                Text(titleKey)
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(DS.primary)
                Text(bodyKey)
                    .font(.system(size: 16, weight: .medium, design: .rounded))
                    .foregroundStyle(DS.textDialog)
                    .multilineTextAlignment(.center)

                HStack(spacing: 12) {
                    // キャンセルボタン：目立たないスタイルで左側に配置し、誤タップを誘いにくくする
                    Button(action: onCancel) {
                        Text("reset_confirm_cancel")
                            .font(.system(size: 16, weight: .semibold, design: .rounded))
                            .foregroundStyle(DS.muted)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 13)
                            .background(
                                RoundedRectangle(cornerRadius: DS.btnRadius)
                                    .fill(Color.black.opacity(0.05))
                            )
                    }
                    .buttonStyle(.plain)

                    // 実行ボタン：警告色（赤系）で塗ってリセットの不可逆性を視覚的に伝える
                    Button(action: onConfirm) {
                        Text("reset_confirm_execute")
                            .font(.system(size: 16, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 13)
                            .background(
                                RoundedRectangle(cornerRadius: DS.btnRadius)
                                    .fill(DS.gaugeWarn)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(28)
            .background(
                RoundedRectangle(cornerRadius: DS.sheetRadius)
                    .fill(DS.card)
                    .shadow(color: .black.opacity(0.12), radius: 20, x: 0, y: 8)
            )
            .padding(.horizontal, 44)
        }
        // 出現・消去をフェードで行う
        .transition(.opacity)
    }
}
