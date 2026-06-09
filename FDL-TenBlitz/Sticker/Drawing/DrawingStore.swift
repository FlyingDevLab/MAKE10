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
//   3. 描画データを Documents/drawing_canvas.json へ永続保存・読み込みする
//   4. キャンバスモード（描画 / ステッカー）の状態を持つ
//
// ★ AppSettings.shared と同じシングルトンパターンを採用している理由 ★
//   DrawingCanvasView と DrawingToolbarView の両方から同じデータにアクセスする必要があるため、
//   1つのインスタンスを共有するシングルトンが最適です。

import SwiftUI

// MARK: - DrawingStore

@Observable
final class DrawingStore {

    // MARK: - Singleton
    // アプリ内どこからでも DrawingStore.shared と書くだけでアクセスできる。
    static let shared = DrawingStore()

    // MARK: - Canvas Mode
    // デフォルトはステッカーモード（既存の操作体験を維持するため）。
    // お絵かきしたいときにユーザーがツールバーのボタンで切り替える。
    var canvasMode: StickerCanvasMode = .sticker

    // MARK: - Drawing State

    /// 確定済みのストローク配列（画面に描かれた線の履歴）
    var strokes: [DrawingStroke] = []

    /// 現在ジェスチャー中のストローク（指を離すと strokes に追加される）
    /// private(set) なので DrawingStore 外からは読み取りのみ可能
    private(set) var activeStroke: DrawingStroke? = nil

    /// 現在選択中の描画色（hex 文字列）。デフォルトは黒。
    var currentColorHex: String = DrawingColor.palette.last(where: { $0.nameKey.contains("black") })?.hex
                                  ?? "#1C1C1E"

    /// 消しゴムモードの ON/OFF
    var isEraserMode: Bool = false

    // MARK: - Stroke Width
    // ← 変更可：ペンと消しゴムの太さをここで調整する
    let penWidth:    CGFloat = 8   // ペンの太さ（pt）← 変更可
    let eraserWidth: CGFloat = 36  // 消しゴムの太さ（pt）← 変更可

    // MARK: - Init
    private init() {
        load()
    }

    // MARK: - Drawing Operations

    /// ジェスチャー開始：新しいストロークを作成する。
    /// - Parameter point: 指を置いた座標
    func beginStroke(at point: DrawingPoint) {
        let hex   = isEraserMode ? DrawingColor.eraserSentinel : currentColorHex
        let width = isEraserMode ? eraserWidth : penWidth
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

    /// 全消去：すべてのストロークを削除して保存する。
    /// ※ 確認ダイアログは DrawingToolbarView 側で表示すること
    func clearAll() {
        strokes     = []
        activeStroke = nil
        save()
    }

    // MARK: - Persistence

    /// 保存先 URL: Documents/drawing_canvas.json
    private var saveURL: URL {
        FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("drawing_canvas.json")
    }

    /// ストローク配列を JSON ファイルに保存する。
    /// .atomic オプションにより、書き込み途中でアプリが落ちてもデータが壊れない。
    func save() {
        do {
            let data = try JSONEncoder().encode(strokes)
            try data.write(to: saveURL, options: .atomic)
        } catch {
            // 保存エラーはデバッグログのみ（ユーザーへの通知は不要）
            print("DrawingStore: 保存エラー: \(error.localizedDescription)")
        }
    }

    /// JSON ファイルからストローク配列を読み込む。
    /// 初回起動など、ファイルが存在しない場合は空配列のまま（エラーではない）。
    func load() {
        do {
            let data = try Data(contentsOf: saveURL)
            strokes = try JSONDecoder().decode([DrawingStroke].self, from: data)
        } catch {
            // ファイル未存在（初回）は正常。それ以外のエラーもログだけ出して続行。
            strokes = []
        }
    }
}
