//
//  DesignSystem.swift
//  FDL-TenBlitz
//
//  Created by 空飛ぶ研究室(FlyingDevLab) on 2026/03/08.
//

// アプリ全体のビジュアルトークン（色・角丸）を列挙型DSに集約したデザインシステム定義ファイル。
// 各所で "DS.〇〇" と書くだけで参照でき、デザイン変更はここだけを修正すればよい。

import SwiftUI

// MARK: - Design System
// アプリ全体の色・角丸・シャドウをここで一元管理する。
// "DS." のプレフィックスで各所から参照する。
// ここだけ変更すればアプリ全体のデザインが変わる。

// インスタンスを持たない純粋なトークン集として列挙型を使用している。
// classやstructではなくenumにすることで誤ってインスタンス化されることを防ぐ。
enum DS {

    // MARK: - Background & Card

    /// アプリの背景色
    static let bg         = Color(red: 0.96, green: 0.94, blue: 0.90)
    /// カード・ダイアログの背景色
    static let card       = Color.white
    /// タイル・選択肢ボタンの背景色
    static let choiceFill = Color(red: 0.99, green: 0.97, blue: 0.93)
    /// テキスト入力欄・コンタクトカードの背景色
    static let inputBg    = Color(red: 0.95, green: 0.95, blue: 0.97)
    /// 設定行の背景色
    static let settingsBg = Color(red: 0.97, green: 0.96, blue: 0.93)

    // MARK: - Brand Colors
    // ブランドカラーは3色体系。primary（青系）とaccent（紫系）はグラデーションにも使用する。
    // blitzColorはBlitzモード専用の赤系強調色で、通常モードには使わない。

    /// プライマリカラー（ボタン・リンク・アクセント）
    static let primary    = Color(red: 0.30, green: 0.50, blue: 0.82)
    /// アクセントカラー（サブ強調・グラデーション）
    static let accent     = Color(red: 0.60, green: 0.42, blue: 0.78)
    /// 10秒モード（Blitz）専用の強調色
    static let blitzColor = Color(red: 0.82, green: 0.30, blue: 0.30)

    // MARK: - Gauge & Status
    // ゲージの色は「良好／警告」の2段階のみ。中間状態（黄色など）は設けず、シンプルに保つ。

    /// ゲージ（良好・正解）
    static let gaugeFull  = Color(red: 0.42, green: 0.72, blue: 0.52)
    /// ゲージ（警告・不正解）
    static let gaugeWarn  = Color(red: 0.80, green: 0.46, blue: 0.40)
    /// ゲージの背景
    static let gaugeBg    = Color(red: 0.86, green: 0.84, blue: 0.80)

    // MARK: - Text Colors
    // テキスト色は用途別に4段階（textPrimary → textBody → textDark → muted）。
    // 数値が近いものは微妙に異なるコントラストを目的としている。

    /// メインテキスト（タイル番号・選択肢ラベルなど）
    static let textPrimary = Color(red: 0.22, green: 0.22, blue: 0.28)
    /// ボディテキスト（説明文・スコア周辺など）
    static let textBody    = Color(red: 0.25, green: 0.25, blue: 0.30)
    /// ダークテキスト（ポリシー本文など）
    static let textDark    = Color(red: 0.20, green: 0.20, blue: 0.25)
    /// ダイアログ内テキスト
    static let textDialog  = Color(red: 0.30, green: 0.30, blue: 0.35)
    /// ミュート（補足・非アクティブ）
    static let muted       = Color(red: 0.52, green: 0.52, blue: 0.54)

    // MARK: - Special Colors

    /// ゴールド（ハイスコア・★・金メダル）
    static let gold        = Color(red: 0.85, green: 0.62, blue: 0.10)

    // MARK: - Corner Radius
    // 角丸は要素の大きさ・重要度に比例して数値を大きくする体系。
    // 同じ画面に複数の角丸を混在させるときは、隣接する要素との差が4以上になるよう選ぶ。

    /// チェックボックスなど極小要素
    static let smallRadius:    CGFloat = 6
    /// アイコンボタン・コピーボタン
    static let iconRadius:     CGFloat = 8
    /// リスト行・選択肢行
    static let rowRadius:      CGFloat = 10
    /// テキスト入力欄・コードブロック
    static let inputRadius:    CGFloat = 12
    /// チップ・設定行ボタン
    static let chipRadius:     CGFloat = 13
    /// タグ・バッジ・カウントモードボタン
    static let tagRadius:      CGFloat = 14
    /// セクションカード内行グループ・ハイスコアカード
    static let sectionRadius:  CGFloat = 16
    /// メインカード・ボタン（大）
    static let cardRadius:     CGFloat = 22
    /// ボタン（大）
    static let btnRadius:      CGFloat = 22
    /// タイムゲージ
    static let gaugeRadius:    CGFloat = 7
    /// シート・サブダイアログ
    static let sheetRadius:    CGFloat = 24
    /// メインダイアログ
    static let dialogRadius:   CGFloat = 28

    // MARK: - Helpers

    /// カード背景（白塗り＋影）を返すヘルパー
    // 複数箇所で同一のカードスタイルを使うため、重複をなくすために切り出している。
    // 呼び出し側は .background(DS.cardShadow()) と書くだけでよい。
    static func cardShadow() -> some View {
        RoundedRectangle(cornerRadius: DS.cardRadius)
            .fill(DS.card)
            .shadow(color: .black.opacity(0.07), radius: 14, x: 0, y: 5)
    }
}
