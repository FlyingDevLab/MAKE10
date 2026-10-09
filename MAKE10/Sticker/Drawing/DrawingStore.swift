//
//  DrawingStore.swift
//  FDL-TenBlitz
//
//  Created by 空飛ぶ研究室(FlyingDevLab) on 2026/06/09.
//

// プレイキャンバスのお絵かきデータを管理するシングルトン。
//
// ★ このクラスの責務 ★
//   1. 現在の描画状態（ストローク配列・選択色・消しゴムモード）を保持する
//   2. ジェスチャーに応じてストロークを追加・更新する
//   3. 開いているページの線を、StickerBookStore を通して保存・読み込みする
//
// ★ 線の位置と太さは「紙に対する割合」（v1.6.0 から）★
//   1.5 までは画面上の位置（pt）で持っていたが、画面の形が変わるとシールとずれてしまった。
//   いまは位置を紙の幅・高さに対する割合（0.0〜1.0）、太さを紙の幅に対する割合で持つ。
//   描くとき（StickerPlayView）と表示するとき（DrawingCanvasView）に、紙の大きさを掛けて pt に戻す。
//   保存先やページの切り替えは StickerBookStore.swift を参照。
//
// ★ AppSettings.shared と同じシングルトンパターンを採用している理由 ★
//   DrawingCanvasView と DrawingToolbarView の両方から同じデータにアクセスする必要があるため、
//   1つのインスタンスを共有するシングルトンが最適です。

import SwiftUI

// MARK: - DrawingStore

@Observable
final class DrawingStore {

    // MARK: - シングルトン
    // アプリ内どこからでも DrawingStore.shared と書くだけでアクセスできる。
    static let shared = DrawingStore()

    // MARK: - 描画状態

    /// 確定済みのストローク配列（画面に描かれた線の履歴）
    var strokes: [DrawingStroke] = []

    /// 現在ジェスチャー中のストローク（指を離すと strokes に追加される）
    /// private(set) なので DrawingStore 外からは読み取りのみ可能
    private(set) var activeStroke: DrawingStroke? = nil

    /// 現在選択中の描画色（hex 文字列）。デフォルトは黒。
    // ★ 以前は $0.nameKey.contains("black") という文字列マッチだったが、
    //   ColorName enum の導入で == .black と型安全に書けるようになった。
    var currentColorHex: String = DrawingColor.palette.last(where: { $0.name == .black })?.hex
                                  ?? "#1C1C1E"

    /// 消しゴムモードの ON/OFF
    var isEraserMode: Bool = false

    // MARK: - 線の太さ
    // ← 変更可：ペンと消しゴムの太さをここで調整する
    let penWidth:    CGFloat = 8   // ペンの太さ（pt）← 変更可
    let eraserWidth: CGFloat = 36  // 消しゴムの太さ（pt）← 変更可

    /// いま表示している紙の幅（pt）。線の太さ（pt）を割合に直すのに使う。StickerPlayView が教える。
    var paperWidth: CGFloat = 1

    /// strokes がどのページの線か（まだ読み込んでいなければ nil）。保存先を間違えないために持っておく。
    private var loadedPage: Int? = nil

    // MARK: - 初期化
    // 線は、シール帳を開いたときに reloadForCurrentPage で読み込む（起動時には読まない）。
    private init() {}

    /// 開いているページの線を読み込む。ページを切り替えたときと、シール帳を開いたときに呼ぶ。
    /// - Parameter portraitSize: この端末を縦にしたときの画面の大きさ（1.5 の線を引っ越すときの基準）
    func reloadForCurrentPage(portraitSize: CGSize) {
        let book = StickerBookStore.shared
        strokes      = book.loadStrokes(page: book.currentPage, portraitSize: portraitSize)
        activeStroke = nil
        loadedPage   = book.currentPage
    }

    // MARK: - 描画操作

    /// ジェスチャー開始：新しいストロークを作成する。
    /// - Parameter point: 指を置いた座標
    func beginStroke(at point: DrawingPoint) {
        let hex   = isEraserMode ? DrawingColor.eraserSentinel : currentColorHex
        // 太さは紙の幅に対する割合で持つ（ファイル冒頭の解説を参照）
        let width = (isEraserMode ? eraserWidth : penWidth) / max(paperWidth, 1)
        activeStroke = DrawingStroke.start(
            at: point,
            colorHex: hex,
            isEraser: isEraserMode,
            width: width
        )
    }

    /// ジェスチャー継続：現在のストロークに点を追加する。
    /// - Parameter point: 指が移動した座標
    func continueStroke(to point: DrawingPoint) {
        // activeStroke が nil のとき（beginStroke が呼ばれていない）は何もしない
        guard activeStroke != nil else { return }
        activeStroke?.points.append(point)
    }

    /// ジェスチャー終了：activeStroke を strokes に確定し、保存する。
    func endStroke() {
        guard let stroke = activeStroke else { return }
        // 点が1つでも線として記録する（タップで点を打てるようにするため）
        strokes.append(stroke)
        activeStroke = nil
        save()
    }

    /// 描画中のストロークを破棄する（保存しない）。
    /// シールを長押しで掴んだときや2本指操作が始まったとき、
    /// 指を置いた瞬間にできてしまった点を取り消すために使う。
    func cancelStroke() {
        activeStroke = nil
    }

    /// 元に戻せる線があるか（ツールバーの ↩︎ ボタンの有効/無効に使う）
    var canUndo: Bool { !strokes.isEmpty }

    /// 元に戻す：最後に確定したストロークを1本消して保存する。
    func undo() {
        guard !strokes.isEmpty else { return }
        strokes.removeLast()
        save()
    }

    /// 全消去：すべてのストロークを削除して保存する。
    /// ※ 確認ダイアログは DrawingToolbarView 側で表示すること
    func clearAll() {
        strokes     = []
        activeStroke = nil
        save()
    }

    // MARK: - 永続化

    /// 開いているページの線を保存する（保存先は StickerBookStore が決める）。
    func save() {
        guard let page = loadedPage else { return }
        StickerBookStore.shared.saveStrokes(strokes, page: page)
    }

}
