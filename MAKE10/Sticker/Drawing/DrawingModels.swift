//
//  DrawingModels.swift
//  FDL-TenBlitz
//
//  Created by 空飛ぶ研究室(FlyingDevLab) on 2026/06/09.
//

// プレイキャンバスのお絵かき機能で使うデータ型を定義するファイル。
//
// ★ このファイルに含まれるもの ★
//   - DrawingPoint     : 画面上の1点の座標
//   - DrawingStroke    : 指1回のなぞり（= 点の列 + 色 + 太さ）
//   - DrawingColor     : クレヨンパレットの1色
//   - StickerCanvasMode: お絵かきモード / ステッカーモードの切り替え
//   - Color(hex:)      : "#FF3B30" 形式の文字列から Color を作る拡張

import SwiftUI

// MARK: - StickerCanvasMode
// プレイキャンバスの操作モードを表す列挙型。
// .drawing のとき → 指でなぞると線が描かれる。ステッカーはタップ不可。
// .sticker のとき → ステッカーを移動・貼り付けできる。描画は不可。
//
// ★ なぜ enum にするのか ★
//   Bool（isDrawingMode）でも実現できますが、
//   将来モードが3つ以上になったときに enum の方が拡張しやすいです。
//   また「どちらかでなければならない」という意図が enum の方が明確です。

enum StickerCanvasMode {
    case drawing  // お絵かきモード（クレヨン）
    case sticker  // ステッカーモード（貼り付け・移動）

    // 現在のモードを切り替えた「反対のモード」を返すヘルパー。
    // DrawingToolbarView のトグルボタンで使う。
    var toggled: StickerCanvasMode {
        self == .drawing ? .sticker : .drawing
    }
}

// MARK: - DrawingPoint
// 画面上の1点の座標を保持する。
// Codable に準拠することで JSON への変換が自動で行われる。
//
// ★ なぜ CGPoint をそのまま使わないのか ★
//   CGPoint は Codable に準拠していないため、
//   JSON 保存ができません。自前の型を定義することで解決しています。

struct DrawingPoint: Codable {
    let x: CGFloat
    let y: CGFloat

    // CGPoint との相互変換ヘルパー
    var cgPoint: CGPoint { CGPoint(x: x, y: y) }

    init(_ cgPoint: CGPoint) {
        self.x = cgPoint.x
        self.y = cgPoint.y
    }
}

// MARK: - DrawingStroke
// 「指1回のなぞり」を表す型。
// 始点から終点までの DrawingPoint 列と、描画属性（色・太さ・消しゴムか否か）を持つ。
//
// ★ isEraser フラグを持つ理由 ★
//   消しゴムも「特殊な色の線」として同じ Stroke 型で扱います。
//   描画時に isEraser = true のストロークだけ blendMode を .clear にすることで
//   透明な「穴」として描画し、消しゴム効果を実現します。

struct DrawingStroke: Codable, Identifiable {
    let id: UUID
    let colorHex: String  // "#FF3B30" 形式（消しゴムの場合は DrawingColor.eraserSentinel）
    let isEraser: Bool
    let width: CGFloat
    var points: [DrawingPoint]

    // 新しいストロークを開始するファクトリメソッド。
    // 開始点 1 点だけを持つストロークを返す。
    static func start(at point: DrawingPoint,
                      colorHex: String,
                      isEraser: Bool,
                      width: CGFloat) -> DrawingStroke {
        DrawingStroke(
            id: UUID(),
            colorHex: colorHex,
            isEraser: isEraser,
            width: width,
            points: [point]
        )
    }
}

// MARK: - DrawingColor
// パレットに並ぶ1色の定義。
// hex は "#RRGGBB" 形式の文字列で保持し、Color への変換は Color(hex:) を使う。

struct DrawingColor {

    // MARK: - ColorName（色の識別子）
    //
    // ★ なぜ String のキーではなく enum なのか ★
    //   以前は nameKey: String にローカライズキーを直接持たせていたが、
    //   これには2つの問題があった。
    //     1. String のまま String.LocalizationValue に変換していたため、
    //        Xcode のビルド時文字列抽出がキーを発見できず、翻訳が引けなかった
    //        （VoiceOver が「drawing_color_red」と読み上げていた）。
    //     2. 色の判別を $0.nameKey.contains("black") のような文字列マッチで
    //        行っていたため、キー名を変えると静かに壊れる作りだった。
    //   enum にすることで、key はリテラルを返して自動抽出の対象になり、
    //   識別は == .black で型安全に書けるようになる。
    enum ColorName {
        case red, orange, yellow, lime, green, cyan
        case blue, purple, pink, brown, black, white

        /// VoiceOver 読み上げ用のローカライズキー。
        /// ★ ここは必ずリテラルで書くこと（変数を返すと自動抽出されない）★
        var key: LocalizedStringKey {
            switch self {
            case .red:    return "drawing_color_red"
            case .orange: return "drawing_color_orange"
            case .yellow: return "drawing_color_yellow"
            case .lime:   return "drawing_color_lime"
            case .green:  return "drawing_color_green"
            case .cyan:   return "drawing_color_cyan"
            case .blue:   return "drawing_color_blue"
            case .purple: return "drawing_color_purple"
            case .pink:   return "drawing_color_pink"
            case .brown:  return "drawing_color_brown"
            case .black:  return "drawing_color_black"
            case .white:  return "drawing_color_white"
            }
        }
    }

    let name: ColorName  // 色の識別子（VoiceOver 用のキーは name.key）
    let hex: String

    // ★ 消しゴムの番兵値 ★
    //   消しゴムストロークの colorHex に格納するダミー値。
    //   実際の描画では blendMode(.clear) を使うため色は参照されない。
    static let eraserSentinel = "eraser"

    // MARK: - 12色クレヨンパレット
    // 子ども向けに定番の12色を選定。
    // hex 値はすべて ← 変更可。
    static let palette: [DrawingColor] = [
        DrawingColor(name: .red,    hex: "#FF3B30"),  // 赤 ← 変更可
        DrawingColor(name: .orange, hex: "#FF9500"),  // オレンジ ← 変更可
        DrawingColor(name: .yellow, hex: "#FFCC00"),  // 黄 ← 変更可
        DrawingColor(name: .lime,   hex: "#86E840"),  // 黄緑 ← 変更可
        DrawingColor(name: .green,  hex: "#34C759"),  // 緑 ← 変更可
        DrawingColor(name: .cyan,   hex: "#5AC8FA"),  // 水色 ← 変更可
        DrawingColor(name: .blue,   hex: "#007AFF"),  // 青 ← 変更可
        DrawingColor(name: .purple, hex: "#AF52DE"),  // 紫 ← 変更可
        DrawingColor(name: .pink,   hex: "#FF2D55"),  // ピンク ← 変更可
        DrawingColor(name: .brown,  hex: "#A2845E"),  // 茶 ← 変更可
        DrawingColor(name: .black,  hex: "#1C1C1E"),  // 黒 ← 変更可
        DrawingColor(name: .white,  hex: "#FFFFFF"),  // 白 ← 変更可
    ]
}

// MARK: - Color(hex:) 拡張
// "#FF3B30" や "FF3B30" 形式の文字列から SwiftUI の Color を生成する。
//
// ★ extension とは？ ★
//   既存の型（ここでは Color）に後からメソッドやイニシャライザを追加できる仕組みです。
//   Color 自体を書き換えずに機能を追加できるため、Apple のフレームワークにも安全に適用できます。

extension Color {
    /// 16進数カラーコード文字列（"#RRGGBB" または "RRGGBB"）から Color を生成する。
    init(hex: String) {
        // "#" や空白を除去して純粋な16進数文字列にする
        let cleaned = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: cleaned).scanHexInt64(&int)
        // 上位8ビットから R, G, B をそれぞれ抽出して 0〜1 の範囲に変換
        let r = Double((int >> 16) & 0xFF) / 255.0
        let g = Double((int >>  8) & 0xFF) / 255.0
        let b = Double( int        & 0xFF) / 255.0
        self.init(red: r, green: g, blue: b)
    }
}
