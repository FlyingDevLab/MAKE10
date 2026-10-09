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

    /// エネルギー（🔥 kcal の数字・獲得バナー・ガチャ／ショップの値段など）
    static let energy      = Color(red: 0.92, green: 0.42, blue: 0.16)

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

// MARK: - 大きな画面（iPad）向けの拡大

// ★ なぜ拡大率を配るのか ★
//   ゲーム画面の部品（カード・ボタン・文字）は iPhone の画面に合わせた固定の大きさで作っている。
//   そのまま iPad に出すと、部品が上に小さく固まり、下ががらんと空いてしまう。
//   そこで「iPhone の何倍の画面か」を拡大率として求め、各部品の大きさに掛けて使う。
//   こうすると iPad でも iPhone と同じ割合（下の余白も同じ割合）の見た目になる。
//
// ★ @Entry とは？ ★
//   EnvironmentValues に自前の値を追加するためのマクロです。
//   親で .environment(\.layoutScale, 1.5) と書くと、子孫の View すべてが
//   @Environment(\.layoutScale) で同じ値を受け取れます（引数で何段もバケツリレーせずに済む）。

extension EnvironmentValues {
    /// iPhone を 1.0 としたゲーム画面の拡大率。iPad など広い場所では 1 より大きくなる。
    @Entry var layoutScale: CGFloat = 1
}

extension DS {
    /// 拡大率の基準にする、iPhone でのゲーム画面（ヘッダーとフッターを除いた部分）の大きさ。
    static let baseContentSize = CGSize(width: 390, height: 660)
    /// 拡大しすぎて部品が大味にならないよう、上限を決めておく。← 変更可
    static let maxLayoutScale: CGFloat = 1.8
    /// この倍率に届かない広さなら拡大しない（拡大率 1 のまま）。← 変更可
    ///
    /// ★ なぜ 1.2 なのか ★
    ///   いちばん大きい iPhone（Pro Max）でも、ゲーム画面は基準の約 1.13 倍しかない。
    ///   1.2 にしておけば、どの iPhone も拡大されず、いままでと同じ見た目のまま。
    ///   iPad や、iPhone Duo を開いたときの広い画面だけが拡大される。
    static let largeScreenThreshold: CGFloat = 1.2

    /// 使える場所が横長（幅 > 高さ）かどうか。
    ///
    /// ★ 端末の向きではなく、幅と高さで決める理由 ★
    ///   iPad の分割表示や iPhone Duo では、端末を縦に持っていてもアプリの場所が横長になることがある。
    ///   「端末がどちらを向いているか」ではなく「アプリが実際に使える場所の形」で決めれば、どの場合も正しく判断できる。
    static func isWide(_ size: CGSize) -> Bool {
        size.width > size.height
    }
}

/// 使える場所が広い（iPad や、iPhone Duo を開いたとき）ときだけ、拡大率を子孫の View に配る ViewModifier。
/// あわせて横幅を「iPhone の幅 × 拡大率」までに抑えて中央に置き、iPhone と同じ縦横の比率を保つ。
/// iPhone では拡大率 1 のままで、見た目は一切変わらない。
///
/// ★ size class（compact / regular）で決めなくなった理由 ★
///   以前は「横幅が regular なら iPad」とみなしていた。
///   しかし iPhone Duo を開いたときや大きな iPhone を横にしたときにも regular になるため、端末の種類の目印には使えない。
///   いまは GeometryReader で測った「実際に使える大きさ」だけで決める。
///   大きさが変わるたび（回転・分割表示・Duo の開閉）に GeometryReader が測り直すので、拡大率もその都度計算し直される。
private struct LargeScreenScaling: ViewModifier {
    func body(content: Content) -> some View {
        GeometryReader { geo in
            let scale = scale(for: geo.size)
            // ★ 横長の場所では幅を絞らない理由 ★
            //   幅を「iPhone の幅 × 拡大率」に絞るのは、縦長の画面で iPhone と同じ比率を保つため。
            //   横長の場所では、各画面が部品を左右に並べ直すので、横幅いっぱいを使えるようにしておく。
            let maxWidth = DS.isWide(geo.size) ? .infinity : DS.baseContentSize.width * scale
            content
                .environment(\.layoutScale, scale)
                .frame(maxWidth: maxWidth)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
    }

    /// 縦・横のうち、余裕が少ない方に合わせて拡大率を決める（はみ出さないように）。
    private func scale(for size: CGSize) -> CGFloat {
        let fit = min(size.width  / DS.baseContentSize.width,
                      size.height / DS.baseContentSize.height)
        guard fit >= DS.largeScreenThreshold else { return 1 }
        return min(fit, DS.maxLayoutScale)
    }
}

extension View {
    /// iPad など広い場所では、使える大きさに合わせて部品を拡大する（LargeScreenScaling を参照）。
    func scalesForLargeScreen() -> some View {
        modifier(LargeScreenScaling())
    }
}

// MARK: - 半透明の塗り（かべがみの上でも透けない）

extension Shape {
    /// 色を薄く重ねた塗り（例: `color.opacity(0.1)`）。
    ///
    /// ★ かべがみを使うときだけ、下にいつもの背景色を敷く理由 ★
    ///   カードやボタンの多くは「背景色の上に色を薄く重ねる」ことで淡い色を出している。
    ///   かべがみ（じぶんの絵）を背景にすると、その薄い色の向こうに絵が透けて、カードやボタンが見にくくなる。
    ///   下にいつもの背景色（DS.bg）を敷けば、かべがみのときもいつもと同じ見た目になる（絵はカードの後ろに隠れる）。
    ///   かべがみを使わないときは何も敷かないので、見た目は以前とまったく同じ。
    func tintFill(_ color: Color) -> some View {
        ZStack {
            if WallpaperStore.shared.isShowing {
                self.fill(DS.bg)
            }
            self.fill(color)
        }
    }
}

// MARK: - 文字の座布団（かべがみの上でも読める）

extension DS {
    /// 座布団が文字からはみ出す幅（pt）。大きくすると、文字のまわりの白い余白が広がる。← 変更可
    static let cushionInset: CGFloat = 8
    /// 座布団の濃さ（0.0〜1.0）。小さくするとかべがみが透けて見え、大きくすると文字が読みやすくなる。← 変更可
    ///
    /// ★ 真っ白（1.0）にしない理由 ★
    ///   せっかく描いた絵をかべがみにしているので、文字の後ろも少しだけ絵が見えるようにしている。
    ///   0.8 なら、絵の線や色がうっすら見えつつ、文字ははっきり読める。
    static let cushionOpacity: Double = 0.8
}

extension View {
    /// かべがみを使っているときだけ、文字の後ろに白い角丸の「座布団」を敷く。
    ///
    /// ★ なぜ座布団が要るのか ★
    ///   カードの外に直接置いた文字（見出し・説明・数など）は、ふだんは無地の背景（DS.bg）の上にあるので読める。
    ///   かべがみ（じぶんの絵）を背景にすると、文字が絵の線や色と重なって読めなくなる。
    ///   文字の後ろにカードと同じ白い座布団を敷けば、どんな絵の上でも読める（少しだけ透かす。DS.cushionOpacity を参照）。
    ///
    /// ★ 座布団を「はみ出させて」描く理由 ★
    ///   padding で文字のまわりを広げると、かべがみを使うかどうかで文字の位置がずれてしまう。
    ///   background の中で座布団だけをマイナスの余白で外へ広げれば、文字の位置と大きさは変わらない。
    ///   かべがみを使わないときは何も描かないので、見た目は以前とまったく同じ。
    func wallpaperCushion() -> some View {
        background {
            if WallpaperStore.shared.isShowing {
                RoundedRectangle(cornerRadius: DS.chipRadius)
                    .fill(DS.card.opacity(DS.cushionOpacity))
                    .padding(-DS.cushionInset)
            }
        }
    }
}
