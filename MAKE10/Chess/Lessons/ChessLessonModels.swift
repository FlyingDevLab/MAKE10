//
//  ChessLessonModels.swift
//  FDL-TenBlitz
//
//  チェスのレッスンの表。chess_lessons.json は Web 版の lessons.js 3 巻を変換したもの。
//  第 1 巻 21・23 回と第 3 巻 2 回の文章だけ、アプリの画面に合わせて直してある
//  （「下の きふ」「上の「あそぶ」タブ」「この ページ」など）。
//  用語の表の記号の欄に日本語の言葉がある行は、その言葉を symJa へ移してある。
//  変換し直すときは同じ直しを入れること。
//
// ★ 文章を Localizable.xcstrings に入れない理由 ★
//   全 57 回で約 900 文あり、アプリ全体の文字列より多い。
//   レッスンの文章は日本語と英語だけで、日本語の端末は日本語、それ以外は英語で出す。
//   第 1 巻は「N は Knight の N」と英語を土台に教えていて、棋譜の記号も言語で変わるので、
//   機械的に他の言語へ訳すと説明が崩れる。
//
// ★ レッスンの盤と棋譜は機械で確かめてある ★
//   全レッスンを、画面と同じ操作で自動で解いて「できた」になることを確認した（2026-11-05）。
//   Web 版のレッスンのコードに同じ乱数の操作を流し、1 操作ごとの盤・言葉・できた・棋譜が
//   同じになることも確認した。文章や盤を書き換えたら、確かめ直すこと。
//

import Foundation

/// 英語と日本語の組。
nonisolated struct ChessText: Decodable, Sendable {
    let en: String
    let ja: String

    /// 端末の言語が日本語か
    static let isJapanese = Bundle.main.preferredLocalizations.first?.hasPrefix("ja") ?? false

    var text: String { Self.isJapanese ? ja : en }

    /// 文章の 2 言語の組から、いまの言語のほうを選ぶ
    static func pick(_ en: String, _ ja: String) -> String { isJapanese ? ja : en }
}

nonisolated struct ChessLessonBook: Decodable, Sendable {
    let volumes: [ChessLessonVolume]

    /// バンドルの表を読む。読めなければ nil。
    static func load(from bundle: Bundle = .main) -> ChessLessonBook? {
        guard let url = bundle.url(forResource: "chess_lessons", withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(ChessLessonBook.self, from: data)
    }
}

nonisolated struct ChessLessonVolume: Decodable, Sendable {
    let no: Int
    let en: String
    let ja: String
    let chapters: [ChessText]
    let lessons: [ChessLesson]

    var title: String { ChessText.pick(en, ja) }
}

nonisolated struct ChessLesson: Decodable, Sendable {
    let chapter: Int
    let en: String
    let ja: String
    let fen: String
    let body: [Block]
    let task: ChessText
    let goal: Goal
    /// true なら相手は動かず、手番が自分のまま続く
    let still: Bool?
    /// 課題の的のマス
    let goals: [String]?
    /// その種類の駒だけ動かせる（'N' など）
    let only: String?

    var title: String { ChessText.pick(en, ja) }

    struct Block: Decodable, Sendable {
        /// 'p' 段落・'pairs' 用語の組・'key' 覚えておく一言
        let t: String
        let en: String?
        let ja: String?
        let items: [PairItem]?

        var text: String { ChessText.pick(en ?? "", ja ?? "") }
    }

    struct PairItem: Decodable, Sendable {
        let en: String
        let ja: String
        /// 棋譜の記号
        let sym: String?
        /// 日本語の画面でだけ記号の欄に出す言葉。無ければ sym
        let symJa: String?
        /// 駒の字。その行の左に白と黒の形が並ぶ
        let pc: String?
    }

    struct Goal: Decodable, Sendable {
        /// squares / moves / setup / replay / chase / free
        let kind: String
        let ask: [String]?
        let ordered: Bool?
        /// squares の印の出し方。'frame' / 'rank'
        let mark: String?
        /// 'value' なら押したときに駒のねうちを言う
        let say: String?
        /// できたときに線を引く 2 マス
        let show: [String]?
        let win: Win?
        /// setup の完成形
        let want: String?
        let palette: [String]?
        /// chase の手数
        let moves: Int?
        let sets: [PieceSet]?
        /// replay の棋譜
        let line: String?
        /// free でコンピュータが黒を持つか
        let cpu: Bool?
    }

    struct Win: Decodable, Sendable {
        let capture: [String]?
        let reach: [String]?
        let line: [String]?
        let flag: String?
        let escape: Bool?
        let status: String?
        let answer: String?
        let answers: [String]?
        /// answers の何手めかごとの一言。無い手は null
        let notes: [ChessText?]?
    }

    struct PieceSet: Decodable, Sendable {
        let en: String
        let ja: String
        let fen: String
        let answer: String?

        var title: String { ChessText.pick(en, ja) }
    }
}
