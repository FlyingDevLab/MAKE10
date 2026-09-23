//
//  DrawingCanvasView.swift
//  FDL-TenBlitz
//
//  Created by 空飛ぶ研究室(FlyingDevLab) on 2026/06/09.
//

// プレイキャンバスの「お絵かきレイヤー」ビュー。
// ステッカーの下に置かれ、DrawingStore のストロークをリアルタイムで描画する。
//
// ★ このビューの責務 ★
//   DrawingStore のストローク配列を Canvas で描画すること「だけ」。
//   指のジェスチャーは StickerPlayView 側でキャンバス全体に付けている。
//   （シールの上をなぞっても線が引けるよう、親の simultaneousGesture で
//     受け取る必要があるため。詳細は StickerPlayView.swift 冒頭を参照）
//
// ★ SwiftUI の Canvas とは？ ★
//   毎フレーム再描画される低レベルな描画面です。
//   多数の線を高速に描くのに向いており、お絵かき用途に最適です。
//   ForEach で View を並べる方法と異なり、Canvas は1つのビューとして扱われ
//   パフォーマンスが高いです。
//
// ★ .drawingGroup() とは？ ★
//   ビューを Metal（GPU）レイヤーにラスタライズします。
//   blendMode(.clear) で「透明な穴」を開けるには Metal レイヤーが必要なため、
//   消しゴム機能の実現に必須です。
//

import SwiftUI

// MARK: - DrawingCanvasView

struct DrawingCanvasView: View {

    // DrawingStore.shared から状態を受け取る。
    // @State にすることで DrawingStore の変化がこのビューの再描画をトリガーする。
    @State private var store = DrawingStore.shared

    var body: some View {
        Canvas { context, _ in
            // ★ 描画順 ★
            // 確定済みストローク → 現在描画中のストローク（activeStroke）の順に描く。
            // こうすることで指を動かしている最中もリアルタイムに線が見える。
            let allStrokes = store.strokes + (store.activeStroke.map { [$0] } ?? [])
            for stroke in allStrokes {
                drawStroke(stroke, in: &context)
            }
        }
        // ★ .drawingGroup() が必要な理由 ★
        //   消しゴム（blendMode: .clear）が正しく動作するには
        //   Metal レイヤー上での合成が必要。このモディファイアがないと
        //   消しゴムが「透明」ではなく「黒」になってしまう。
        .drawingGroup()
        // 親（StickerPlayView）のジェスチャーがタッチを受け取れるよう、
        // このビュー自体はヒットテストに参加しない
        .allowsHitTesting(false)
    }

    // MARK: - 描画

    /// 1本のストロークを GraphicsContext に描画するヘルパー。
    /// - Parameters:
    ///   - stroke: 描画するストローク
    ///   - context: Canvas の描画コンテキスト（inout で受け取り blendMode を変更する）
    private func drawStroke(_ stroke: DrawingStroke, in context: inout GraphicsContext) {
        // ★ 消しゴムの仕組み ★
        //   blendMode を .clear にすることで、描画した領域が「透明な穴」になる。
        //   .drawingGroup() があるときだけ正しく動作する。
        if stroke.isEraser {
            context.blendMode = .clear
        } else {
            context.blendMode = .normal
        }

        let color = stroke.isEraser
            ? Color.clear  // 消しゴムは色不要（blendMode.clear で処理）
            : Color(hex: stroke.colorHex)

        let style = StrokeStyle(
            lineWidth: stroke.width,
            lineCap:   .round,   // 線の端を丸くする（クレヨンらしい柔らかさ）
            lineJoin:  .round    // 折れ曲がり部分も丸くする
        )

        if stroke.points.count == 1 {
            // ★ タップ（点）の描画 ★
            //   点が1つしかない場合は Drag ではなくタップ。
            //   円を描くことで「点」として表現する。
            let pt = stroke.points[0].cgPoint
            let half = stroke.width / 2
            let rect = CGRect(x: pt.x - half, y: pt.y - half,
                              width: stroke.width, height: stroke.width)
            if stroke.isEraser {
                // 消しゴムタップ：blendMode.clear で円形に消す
                context.fill(Path(ellipseIn: rect), with: .color(Color.white))
            } else {
                context.fill(Path(ellipseIn: rect), with: .color(color))
            }
        } else {
            // ★ 通常の線の描画 ★
            //   点の列をつなぐパスを作って stroke（線として描画）する。
            var path = Path()
            path.move(to: stroke.points[0].cgPoint)
            for point in stroke.points.dropFirst() {
                path.addLine(to: point.cgPoint)
            }
            context.stroke(path, with: .color(color), style: style)
        }
    }
}
