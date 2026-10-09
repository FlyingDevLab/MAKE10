//
//  StickerBookStore.swift
//  FDL-TenBlitz
//
//  Created by 空飛ぶ研究室(FlyingDevLab) on 2026/10/09.
//
//  シール帳の「ページ」（1〜10ページ）を保存・読み込みするシングルトン。
//  1ページは「紙の縦横比・背景色・貼ったシール・描いた線」でできている。
//
//  役割分担:
//    - StickerBookStore（このファイル）: ページの保存・読み込み、開いているページ、1.5 からの引っ越し
//    - StickerStore                    : シールの出し入れ（開いているページのシールは、このファイルが持つ）
//    - DrawingStore                    : 線を描く（開いているページの線を、このファイルから読み書きする）
//    - StickerPlayView                 : 紙を表示し、ページを切り替える
//
//  ★ 保存の形 ★
//    Documents/StickerBook/book.json        … 全ページの「紙の縦横比・背景色・シール」（小さいので1つのファイル）
//    Documents/StickerBook/strokes-01.json  … 1ページ目の線（線は点が多くて大きいので、ページごとに分ける）
//    線をページごとに分けているのは、開いているページの線だけを読み込めば済むようにするため（メモリの節約）。
//
//  ★ 位置はすべて「紙に対する割合（0.0〜1.0）」で持つ ★
//    シールは 1.5 から割合で持っていた。線は 1.5 では画面上の位置（pt）で持っていたので、
//    画面の形が変わる（iPad を回す・iPhone Duo を開く）と、線とシールの位置がずれてしまった。
//    1.6 からは線も割合で持ち、線の太さも「紙の幅に対する割合」で持つ。
//    紙は縦横比を決めて（paperAspect）、どんな形の場所でもその比率のまま中央に置くので、絵がゆがまない。
//
//  ★ 1.5 からの引っ越し（だいじな絵を失わないために）★
//    1.5 では、シールを UserDefaults（UDKey.playStickers）、背景色を UDKey.playBoardBackground、
//    線を Documents/drawing_canvas.json に保存していた。これを1ページ目に移す。
//      ・シールと背景色 … 起動したときにすぐ移す（割合なので、そのまま使える）
//      ・線             … はじめてシール帳を開いたときに移す（pt を割合に直すには、描いたときの紙の大きさが要るため）
//    1.5 は縦向き・全画面だけだったので、描いたときの紙は「この端末を縦にしたときの画面」と同じ大きさ。
//    それを基準に割合へ直す。
//    古いデータは消さずに残しておく（移すのに失敗しても、元の絵が失われないように）。

import SwiftUI
import UIKit

// MARK: - StickerBookPage

/// シール帳の1ページ分（線を除く）。線は大きいので別のファイルに分けている（上の「保存の形」を参照）。
struct StickerBookPage: Codable {
    /// 紙の縦横比（幅 ÷ 高さ）。まだ一度も開いていないページは nil（開いたときに、その端末の縦の比率で決まる）。
    var paperAspect: Double?
    /// 背景色の番号（StickerPlayView の palette の何番目か）。
    var background: Int = 0
    /// 貼ったシール。位置は紙に対する割合。
    var stickers: [StickerStore.Sticker] = []
}

// MARK: - StickerBookStore

// @Observable / シングルトンの解説は AppSettings.swift 冒頭を参照
@Observable
final class StickerBookStore {

    static let shared = StickerBookStore()

    // MARK: ⚙️ 調整パラメータ

    /// シール帳のページ数。← 変更可（減らすと、それより後ろのページは表示されなくなる。保存データは消えない）
    static let pageCount = 10

    // MARK: 状態

    /// 全ページの「紙の縦横比・背景色・シール」。小さいので、全ページぶんをいつも持っておく。
    private(set) var pages: [StickerBookPage]

    /// いま開いているページ（0 始まり。画面には +1 して「1 / 10」のように出す）。
    private(set) var currentPage: Int {
        didSet { UserDefaults.standard.set(currentPage, forKey: UDKey.stickerBookCurrentPage) }
    }

    // MARK: 初期化

    private init() {
        pages = Array(repeating: StickerBookPage(), count: Self.pageCount)
        let saved = UserDefaults.standard.integer(forKey: UDKey.stickerBookCurrentPage)
        currentPage = min(max(saved, 0), Self.pageCount - 1)

        if let data   = try? Data(contentsOf: Self.bookURL),
           let loaded = try? JSONDecoder().decode([StickerBookPage].self, from: data) {
            // ページ数を変えたときにも読めるよう、足りない分は空のページで埋め、多い分は持っておくだけにする
            for (i, page) in loaded.enumerated() where i < pages.count {
                pages[i] = page
            }
        } else if !UserDefaults.standard.bool(forKey: UDKey.stickerBookMigrated160) {
            migrateStickersFrom15()
        }
    }

    // MARK: 開いているページ

    /// 開いているページのシール。StickerStore.playStickers はこれを読み書きする。
    var currentStickers: [StickerStore.Sticker] {
        get { pages[currentPage].stickers }
        set { pages[currentPage].stickers = newValue }
    }

    /// 開いているページの背景色の番号。
    var currentBackground: Int {
        get { pages[currentPage].background }
        set {
            pages[currentPage].background = newValue
            saveBook()
        }
    }

    /// 開いているページの紙の縦横比。まだ決まっていなければ nil。
    var currentPaperAspect: Double? { pages[currentPage].paperAspect }

    /// 開いているページの紙の縦横比を決める（まだ決まっていないときだけ）。
    /// - Parameter portraitSize: この端末を縦にしたときの画面の大きさ（StickerPlayView が渡す）
    func fixPaperAspectIfNeeded(portraitSize: CGSize) {
        guard pages[currentPage].paperAspect == nil, portraitSize.height > 0 else { return }
        pages[currentPage].paperAspect = Double(portraitSize.width / portraitSize.height)
        saveBook()
    }

    /// ページを切り替える。線の読み込みは DrawingStore が行う（DrawingStore.reloadForCurrentPage を参照）。
    func openPage(_ index: Int) {
        guard pages.indices.contains(index), index != currentPage else { return }
        currentPage = index
    }

    /// 全ページに貼ってあるシールの数（絵文字ごと）。「もっているシール」の数え上げに使う（StickerStore.ownedCounts）。
    func stickerCountsInAllPages() -> [String: Int] {
        var counts: [String: Int] = [:]
        for page in pages {
            for s in page.stickers { counts[s.emoji, default: 0] += 1 }
        }
        return counts
    }

    // MARK: 保存

    /// 全ページの「紙の縦横比・背景色・シール」を保存する。
    func saveBook() {
        do {
            try FileManager.default.createDirectory(at: Self.folderURL, withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(pages)
            try data.write(to: Self.bookURL, options: .atomic)
        } catch {
            print("StickerBookStore: 保存エラー: \(error.localizedDescription)")
        }
    }

    /// あるページの線を読み込む。位置と太さは紙に対する割合。
    /// 1ページ目にまだ線のファイルがなく、1.5 の線が残っていれば、ここで割合に直して引っ越す。
    /// - Parameter portraitSize: この端末を縦にしたときの画面の大きさ（1.5 の線を直すときの基準）
    func loadStrokes(page index: Int, portraitSize: CGSize) -> [DrawingStroke] {
        let url = Self.strokesURL(page: index)
        if let data    = try? Data(contentsOf: url),
           let strokes = try? JSONDecoder().decode([DrawingStroke].self, from: data) {
            return strokes
        }
        if index == 0, let migrated = migrateStrokesFrom15(portraitSize: portraitSize) {
            saveStrokes(migrated, page: 0)
            return migrated
        }
        return []
    }

    /// あるページの線を保存する。
    func saveStrokes(_ strokes: [DrawingStroke], page index: Int) {
        do {
            try FileManager.default.createDirectory(at: Self.folderURL, withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(strokes)
            try data.write(to: Self.strokesURL(page: index), options: .atomic)
        } catch {
            print("StickerBookStore: 保存エラー: \(error.localizedDescription)")
        }
    }

    // MARK: リセット

    /// 「さいしょから はじめる」で、全ページ（シール・線・背景色・紙の比率）を消して、1ページ目に戻す。
    /// 1.5 からの引っ越しが済んだ印（UDKey.stickerBookMigrated160）は残す。
    /// 残さないと、次の起動で（もう消した）1.5 のデータを探して、引っ越しをやり直そうとしてしまう。
    func reset() {
        pages = Array(repeating: StickerBookPage(), count: Self.pageCount)
        currentPage = 0
        try? FileManager.default.removeItem(at: Self.folderURL)
        // 1.5 の線も消す。残しておくと、1ページ目の線のファイルがないときに、消したはずの絵が引っ越してきてしまう
        try? FileManager.default.removeItem(at: Self.legacyDrawingURL)
        UserDefaults.standard.set(true, forKey: UDKey.stickerBookMigrated160)
    }

    // MARK: 1.5 からの引っ越し

    /// 1.5 のシールと背景色を1ページ目に移す（起動したときに1回だけ）。
    /// 1.5 のシールは、紙（＝画面）に対する割合で保存されているので、そのまま使える。
    private func migrateStickersFrom15() {
        if let data    = UserDefaults.standard.data(forKey: UDKey.playStickers),
           let decoded = try? JSONDecoder().decode([StickerStore.Sticker].self, from: data) {
            pages[0].stickers = decoded
        }
        pages[0].background = UserDefaults.standard.integer(forKey: UDKey.playBoardBackground)
        saveBook()
        // book.json を書けたことを確かめてから印を付ける（書けなければ、次の起動でもう一度移す）
        if FileManager.default.fileExists(atPath: Self.bookURL.path) {
            UserDefaults.standard.set(true, forKey: UDKey.stickerBookMigrated160)
        }
    }

    /// 1.5 の線（画面上の pt）を、紙に対する割合に直して返す。1.5 の線がなければ nil。
    /// - Parameter portraitSize: この端末を縦にしたときの画面の大きさ（1.5 で描いたときの紙の大きさ）
    private func migrateStrokesFrom15(portraitSize: CGSize) -> [DrawingStroke]? {
        guard portraitSize.width > 0, portraitSize.height > 0,
              let data   = try? Data(contentsOf: Self.legacyDrawingURL),
              let legacy = try? JSONDecoder().decode([DrawingStroke].self, from: data),
              !legacy.isEmpty else { return nil }
        let w = portraitSize.width
        let h = portraitSize.height
        // 1ページ目の紙は、1.5 で描いたときと同じ縦横比にする（絵がゆがまないように）
        if pages[0].paperAspect == nil {
            pages[0].paperAspect = Double(w / h)
            saveBook()
        }
        return legacy.map { stroke in
            DrawingStroke(
                id:       stroke.id,
                colorHex: stroke.colorHex,
                isEraser: stroke.isEraser,
                width:    stroke.width / w,   // 太さは紙の幅に対する割合
                points:   stroke.points.map { DrawingPoint(CGPoint(x: $0.x / w, y: $0.y / h)) }
            )
        }
    }

    // MARK: 保存先

    /// Documents/StickerBook/
    private static var folderURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("StickerBook", isDirectory: true)
    }

    /// Documents/StickerBook/book.json
    private static var bookURL: URL { folderURL.appendingPathComponent("book.json") }

    /// Documents/StickerBook/strokes-01.json（ページ番号は 1 始まり・2桁）
    private static func strokesURL(page index: Int) -> URL {
        folderURL.appendingPathComponent(String(format: "strokes-%02d.json", index + 1))
    }

    /// 1.5 の線の保存先（Documents/drawing_canvas.json）。引っ越しのときに読むだけで、消さない。
    private static var legacyDrawingURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("drawing_canvas.json")
    }
}
