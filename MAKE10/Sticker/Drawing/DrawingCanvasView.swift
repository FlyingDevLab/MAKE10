//
//  DrawingCanvasView.swift
//  FDL-TenBlitz
//
//  Created by 空飛ぶ研究室(FlyingDevLab) on 2026/06/09.
//

// プレイキャンバスの「お絵かきレイヤー」ビュー。
// ステッカーの下に置かれ、指でなぞった線をリアルタイムで描画する。
//
// ★ このビューの責務 ★
//   1. DrawingStore のストローク配列を Canvas で描画する
//   2. DragGesture で指の動きを DrawingStore に伝える
//   3. ジェスチャーは常時受け付ける（シールが上に乗っている場所は
//      StickerPlayView 側のヒットテストがシール優先で奪うため、
//      ここで有効/無効を切り替える必要はない）
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
// ★ 以前は StickerCanvasMode（お絵かき⇄シール移動の排他モード）で
//   ジェスチャーの有効/無効を切り替えていたが、
//   「お絵かき中でもシールを動かしたい」という要望により廃止した。
//   お絵かきは常時有効にし、シール側の DraggablePlayStickerView が
//   絵文字の描画範囲だけをヒットテスト領域として持つため、
//   シールの上を触ればシールが、それ以外の場所をなぞればここで
//   線が引かれる、という自然な棲み分けになる。

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
        // お絵かきジェスチャーは常時有効
        .gesture(drawingGesture)
    }

    // MARK: - ジェスチャー

    /// 指でなぞって線を描くジェスチャー。
    /// minimumDistance: 0 にすることでタップ（点）も記録できる。
    private var drawingGesture: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { value in
                let point = DrawingPoint(value.location)
                if store.activeStroke == nil {
                    // 指を置いた瞬間：新しいストロークを開始
                    store.beginStroke(at: point)
                } else {
                    // 指を動かしている最中：現在のストロークに点を追加
                    store.continueStroke(to: point)
                }
            }
            .onEnded { _ in
                // 指を離した瞬間：ストロークを確定して保存
                store.endStroke()
            }
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
