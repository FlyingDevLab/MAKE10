//
//  DesignSystem.swift
//  FDL-TenBlitz
//
//  Created by 空飛ぶ研究室(FlyingDevLab) on 2026/03/08.
//

// アプリ全体のビジュアルトークン（色・角丸）を列挙型DSに集約したデザインシステム定義ファイル。
// 各所で "DS.〇〇" と書くだけで参照でき、デザイン変更はここだけを修正すればよい。
//
// ★ デザイントークンとは？ ★
//   色・角丸・余白などの「デザインの最小単位の値」のことです。
//   たとえば「ボタンの背景は青」という情報を、コードのあちこちに
//   Color(red: 0.30, green: 0.50, blue: 0.82) と書くのではなく、
//   DS.primary という名前で一箇所に定義してから参照します。
//   こうすることで「青を少し濃くしたい」ときに DS.primary の1行だけを
//   変えればアプリ全体に反映されます（マジックナンバーの排除）。
//
// case のない enum を「名前空間」として使う理由は ScoreBoard.swift 冒頭を参照。

import SwiftUI

// MARK: - DS

enum DS {

    // MARK: 背景・カード
    //
    // 背景・カード・入力欄など、コンテンツを「受け皿」として支える色群。
    // bg よりも card の方がわずかに明るく、階層（奥←→手前）を感じさせる。

    /// アプリ全体の最背面の背景色（クリーム系のオフホワイト）
    static let bg         = Color(red: 0.96, green: 0.94, blue: 0.90)
    /// カード・ダイアログの背景色（純白。bg より明るく浮いて見える）
    static let card       = Color.white
    /// タイル・選択肢ボタンの背景色（bg より少し温かみのある薄い黄みがかった白）
    static let choiceFill = Color(red: 0.99, green: 0.97, blue: 0.93)
    /// テキスト入力欄・コンタクトカードの背景色（やや青みがかったクールなグレー）
    static let inputBg    = Color(red: 0.95, green: 0.95, blue: 0.97)
    /// 設定画面の行背景色（bg に近いが少し明るめ）
    static let settingsBg = Color(red: 0.97, green: 0.96, blue: 0.93)

    // MARK: ブランドカラー
    //
    // ブランドカラーは3色体系。
    // primary（青系）とaccent（紫系）はグラデーションにも使用する。
    // blitzColor は Blitz モード専用の赤系強調色で、通常モードには使わない。
    //
    // ★ ブランドカラーを3色に絞る理由 ★
    //   色が多すぎると画面がうるさくなります。
    //   強調したいものに primary を使い、補助的な強調に accent を使い、
    //   Blitz（緊張感が必要な場面）だけ blitzColor という使い分けで
    //   「何が重要か」をユーザーが直感的に把握できるようにしています。

    /// プライマリカラー（メインボタン・リンク・重要な数字など）
    static let primary    = Color(red: 0.30, green: 0.50, blue: 0.82)
    /// アクセントカラー（サブ強調・グラデーションの終端色・ハイスコア表示など）
    static let accent     = Color(red: 0.60, green: 0.42, blue: 0.78)
    /// 10秒モード（Blitz）専用の強調色（赤系。緊張感・スピード感を演出）
    static let blitzColor = Color(red: 0.82, green: 0.30, blue: 0.30)

    // MARK: ゲージ・状態色
    //
    // ゲージの色は「良好／警告」の2段階のみ。
    // 中間状態（黄色など）は設けず、シンプルに保つ。
    //
    // ★ 2段階に絞る理由 ★
    //   「緑→黄→赤」の3段階も一般的ですが、子ども向けアプリでは
    //   「大丈夫 / やばい」の二択の方が直感的に伝わります。

    /// ゲージ満タン・正解・良好（緑系）
    static let gaugeFull  = Color(red: 0.42, green: 0.72, blue: 0.52)
    /// ゲージ警告・不正解・残り少ない（赤系）
    static let gaugeWarn  = Color(red: 0.80, green: 0.46, blue: 0.40)
    /// ゲージ自体の背景（塗りつぶされていない部分の色）
    static let gaugeBg    = Color(red: 0.86, green: 0.84, blue: 0.80)

    // MARK: テキスト色
    //
    // テキスト色は用途別に4段階（textPrimary → textBody → textDark → muted）。
    // 微妙なコントラストの差によって、情報の重要度を視覚的に区別する。
    //
    // ★ なぜこんなに似た色が並ぶのか ★
    //   画面の中で「タイトル」「本文」「補足」「非アクティブ」を区別するために
    //   意図的に濃さを変えています。ぱっと見は同じに見えますが、
    //   並べると違いがわかり、読み手が無意識に情報の優先度を把握できます。

    /// メインテキスト（タイル番号・選択肢ラベルなど。最も目立つ）
    static let textPrimary = Color(red: 0.22, green: 0.22, blue: 0.28)
    /// ボディテキスト（説明文・スコア周辺など。やや控えめ）
    static let textBody    = Color(red: 0.25, green: 0.25, blue: 0.30)
    /// ダークテキスト（プライバシーポリシーなど長文向け。読みやすさ重視）
    static let textDark    = Color(red: 0.20, green: 0.20, blue: 0.25)
    /// ダイアログ内テキスト（ポップアップ内の本文）
    static let textDialog  = Color(red: 0.30, green: 0.30, blue: 0.35)
    /// ミュート（補足情報・非アクティブ状態。最も薄くて控えめ）
    static let muted       = Color(red: 0.52, green: 0.52, blue: 0.54)

    // MARK: 特別色

    /// ゴールド（ハイスコア・★・金メダル・$1 完成など特別な達成を祝う色）
    static let gold        = Color(red: 0.85, green: 0.62, blue: 0.10)

    // MARK: 角丸
    //
    // 角丸は要素の大きさ・重要度に比例して数値を大きくする体系。
    // 同じ画面に複数の角丸を混在させるときは、隣接する要素との差が4以上になるよう選ぶ。
    //
    // ★ なぜ角丸を統一するのか ★
    //   バラバラな角丸の値が混在すると画面全体が「なんとなくちぐはぐ」に見えます。
    //   あらかじめ体系を決めて名前を付けておくことで、
    //   「このボタンは btnRadius」「このカードは cardRadius」と
    //   迷わずに選べるようになります。
    //
    // ★ CGFloat とは？ ★
    //   Core Graphics（Apple の描画フレームワーク）で使う浮動小数点数型です。
    //   pt（ポイント）単位で、1pt = 画面の論理1ピクセル（Retina では2〜3px）。

    /// チェックボックスなど極小要素（6pt）
    static let smallRadius:    CGFloat = 6
    /// タイムゲージ（7pt。細長い形状なので小さめ）
    static let gaugeRadius:    CGFloat = 7
    /// アイコンボタン・コピーボタン（8pt）
    static let iconRadius:     CGFloat = 8
    /// リスト行・選択肢行（10pt）
    static let rowRadius:      CGFloat = 10
    /// テキスト入力欄・コードブロック（12pt）
    static let inputRadius:    CGFloat = 12
    /// チップ・設定行ボタン（13pt）
    static let chipRadius:     CGFloat = 13
    /// タグ・バッジ・カウントモードボタン（14pt）
    static let tagRadius:      CGFloat = 14
    /// セクションカード内行グループ・ハイスコアカード（16pt）
    static let sectionRadius:  CGFloat = 16
    /// メインカード（22pt）
    static let cardRadius:     CGFloat = 22
    /// ボタン（大）（22pt。cardRadius と同値で揃えている）
    static let btnRadius:      CGFloat = 22
    /// シート・サブダイアログ（24pt）
    static let sheetRadius:    CGFloat = 24
    /// メインダイアログ（28pt。最も大きな要素なので最大の角丸）
    static let dialogRadius:   CGFloat = 28

    // MARK: ヘルパー

    /// カード背景（白塗り＋影）を返すヘルパー。
    /// 複数箇所で同一のカードスタイルを使うため、重複をなくすために切り出している。
    /// 呼び出し側は .background(DS.cardShadow()) と書くだけでよい。
    ///
    /// ★ some View とは？ ★
    ///   「何らかの View 型を返す」という意味です（不透明型）。
    ///   RoundedRectangle に .fill や .shadow を付けると型が複雑になりますが、
    ///   some View にすることで呼び出し側がその複雑な型を知らなくて済みます。
    static func cardShadow() -> some View {
        RoundedRectangle(cornerRadius: DS.cardRadius)
            .fill(DS.card)
            // shadow: x:0, y:5 で「真下に落ちる影」を表現（浮いているように見える）
            .shadow(color: .black.opacity(0.07), radius: 14, x: 0, y: 5)
    }
}
