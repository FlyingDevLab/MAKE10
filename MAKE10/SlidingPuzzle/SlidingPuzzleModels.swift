//
//  SlidingPuzzleModels.swift
//  FDL-TenBlitz
//
//  Created by 空飛ぶ研究室(FlyingDevLab) on 2026/11/03.
//

// 4×5 の盤から 2×2 の駒を下の出口へ運び出すスライドパズルの、データ型と3つのゲームの表。
//
// ★ 3つのゲームが同じ盤を使っている ★
//   クロツキ（KLOTSKI）・箱入り娘・華容道 は、盤も駒の構成もまったく同じ
//   （2×2 が1つ・2×1 が1つ・1×2 が4つ・1×1 が4つ）で、違うのは
//   始まりの配置と、駒の名札・色・文言だけ。
//   そこで盤を動かす仕組み（SlidingPuzzleViewModel）と画面（SlidingPuzzleView）を1つだけ置き、
//   このファイルの SlidingPuzzleKind に「配置・名札・色」を持たせている。
//   （Web 版 flyingdevlab.com/kids/ の /shared/klotski.js と同じ分け方）
//
// ★ むずかしさは標準だけ ★
//   Web 版の箱入り娘には4段（標準・難関・おこ・激おこ）があるが、アプリは標準だけにしている。
//   箱入り娘の標準は、華容道と同じ「橫刀立馬」の並び（最短81手）。名札と色だけが違う。
//
// ★ 最短の手数は総当たりで確かめた値 ★
//   クロツキ 32手 / 華容道 81手 / 箱入り娘（標準）81手。
//   同じ駒を続けて動かしている間は1手と数える（このパズルの慣習。SlidingPuzzleViewModel を参照）。
//   配置を変えたら必ず解き直し、par も書き換えること。
//
// ★ 駒の文字は訳さない ★
//   箱入り娘の駒は日本語（ふりがな付き）、華容道の駒は繁體中文（注音付き）、
//   クロツキの駒は文字なし。どの言語で遊んでも同じ。駒の文字はそのオモチャの一部であり、
//   訳すと別のパズルになってしまうため（Web 版と同じ）。画面のボタンや説明だけを訳している。

import SwiftUI

// MARK: - 駒

/// 駒1つ分。盤はマスの配列を持たず、駒を { x, y, w, h } の長方形としてだけ持つ
/// （重なりは長方形どうしの交差で判定する。SlidingPuzzleViewModel.isFree を参照）。
struct SlidingPiece: Identifiable, Equatable {
    let id: String
    let w:  Int
    let h:  Int
    var x:  Int
    var y:  Int
    /// 駒の表に出す文字。nil なら何も出さない（クロツキ）
    var face: String? = nil
    /// face に振る読み（ふりがな・注音）。nil なら振らない
    var ruby: String? = nil
    /// VoiceOver で読む名前（翻訳しない。駒の文字と同じ理由）
    let label: String
    /// 色と文字の色
    let fill:  Color
    let ink:   Color
}

// MARK: - 見た目

/// ゲームごとの色。盤のまわりの台・枠・盤の底・強調の色。
struct SlidingPuzzleTheme {
    let ground:    Color    // 盤を載せる台の色
    let groundDeep: Color   // 手数の札・ボタンの色
    let text:      Color    // 台の上の文字
    let muted:     Color    // 台の上の補助の文字
    let rim:       Color    // 盤の枠
    let rimHi:     Color    // 枠の光が当たる側
    let recess:    Color    // 盤の底（出口もこの色）
    let accent:    Color    // 強調（出口の名前・記録）
    let accentInk: Color    // 強調の色のボタンに乗せる文字
    /// 駒の文字を書く言語。漢字の字形（關・黃 など）をその国の形で出すために使う
    let typesetting: Locale.Language?
}

// MARK: - 3つのゲーム

/// 3つのゲーム。rawValue は記録のキーに使うので変えないこと。
enum SlidingPuzzleKind: String, CaseIterable, Identifiable {
    case klotski      // クロツキ（英語圏の名前。文字のない積み木。最短32手・いちばんやさしい）
    case hakoiri      // 箱入り娘（日本。娘と奉公人。標準の並びで最短81手）
    case huarongdao   // 華容道（中国。三國演義の武将。橫刀立馬の並びで最短81手）

    var id: String { rawValue }

    /// ゲームの名前（タイルとヘッダー）
    var title: LocalizedStringKey {
        switch self {
        case .klotski:    return "klotski_title"
        case .hakoiri:    return "hakoiri_title"
        case .huarongdao: return "huarongdao_title"
        }
    }

    /// 盤の上に出す、何をすればよいかの一言
    var tagline: LocalizedStringKey {
        switch self {
        case .klotski:    return "klotski_tagline"
        case .hakoiri:    return "hakoiri_tagline"
        case .huarongdao: return "huarongdao_tagline"
        }
    }

    /// 最短の手数（総当たりで確かめた値。このファイル冒頭を参照）
    var par: Int {
        switch self {
        case .klotski:    return 32
        case .hakoiri:    return 81
        case .huarongdao: return 81
        }
    }

    /// 出口へ運ぶ駒の id
    var goalID: String { pieces[0].id }
    /// その駒が収まるべき左上のマス。出口は下辺の中央2マスなので x = 1、2マスの高さが最下段に収まる y = 3
    var goal: (x: Int, y: Int) { (1, 3) }

    /// 盤の上と下に出す地名（華容道だけ）。曹操は上（赤壁）から下（江陵）へ逃げる。
    /// 物語の中の地名なので訳さない。他の2つは出口の名前を訳して出す（SlidingPuzzleView を参照）。
    var placeNames: (top: String, bottom: String)? {
        self == .huarongdao ? ("赤壁", "江陵") : nil
    }

    // MARK: 色

    var theme: SlidingPuzzleTheme {
        switch self {
        // クリーム色の台に、色の積み木。ハブ（アプリの地）と同じ明るさ
        case .klotski:
            return SlidingPuzzleTheme(
                ground: Color(red: 1.00, green: 1.00, blue: 1.00),
                groundDeep: Color(red: 0.96, green: 0.94, blue: 0.90),
                text: Color(red: 0.22, green: 0.22, blue: 0.26),
                muted: Color(red: 0.52, green: 0.52, blue: 0.53),
                // 枠を盤の底より一段濃くして、下の出口（底の色で塗った切り欠き）が見えるようにする
                rim: Color(red: 0.80, green: 0.75, blue: 0.67),
                rimHi: Color(red: 0.88, green: 0.84, blue: 0.77),
                recess: Color(red: 0.93, green: 0.91, blue: 0.87),
                accent: Color(red: 0.30, green: 0.50, blue: 0.82),
                accentInk: .white,
                typesetting: nil)
        // 藍の台に、欅の枠と木の駒（娘だけ朱漆）
        case .hakoiri:
            return SlidingPuzzleTheme(
                ground: Color(red: 0.11, green: 0.16, blue: 0.26),
                groundDeep: Color(red: 0.07, green: 0.10, blue: 0.18),
                text: Color(red: 0.95, green: 0.92, blue: 0.86),
                muted: Color(red: 0.65, green: 0.69, blue: 0.78),
                rim: Color(red: 0.66, green: 0.45, blue: 0.25),
                rimHi: Color(red: 0.81, green: 0.60, blue: 0.37),
                recess: Color(red: 0.17, green: 0.11, blue: 0.07),
                accent: Color(red: 0.93, green: 0.79, blue: 0.42),
                accentInk: Color(red: 0.23, green: 0.14, blue: 0.08),
                typesetting: Locale.Language(identifier: "ja"))
        // 栗色の台に、紫檀の枠と漆の駒（曹操だけ朱に金文字）
        case .huarongdao:
            return SlidingPuzzleTheme(
                ground: Color(red: 0.16, green: 0.10, blue: 0.09),
                groundDeep: Color(red: 0.11, green: 0.07, blue: 0.06),
                text: Color(red: 0.95, green: 0.91, blue: 0.83),
                muted: Color(red: 0.73, green: 0.64, blue: 0.55),
                rim: Color(red: 0.36, green: 0.20, blue: 0.15),
                rimHi: Color(red: 0.49, green: 0.29, blue: 0.21),
                recess: Color(red: 0.13, green: 0.07, blue: 0.07),
                accent: Color(red: 0.89, green: 0.73, blue: 0.42),
                accentInk: Color(red: 0.23, green: 0.14, blue: 0.08),
                typesetting: Locale.Language(identifier: "zh-Hant"))
        }
    }

    // MARK: 配置

    /// 始まりの配置。左上を (0, 0) とするマス目の位置。先頭が出口へ運ぶ駒。
    var pieces: [SlidingPiece] {
        switch self {
        // 最短32手。空き2マスが出口の真上にあるので、何をすればいいかが見た瞬間に分かる。
        // 左右対称の形を選んである。駒には文字を書かず、大きさと色だけで区別する。
        case .klotski:
            let big  = Color(red: 0.89, green: 0.40, blue: 0.31)
            let tall = Color(red: 0.30, green: 0.50, blue: 0.82)
            let wide = Color(red: 0.35, green: 0.66, blue: 0.42)
            let unit = Color(red: 0.93, green: 0.73, blue: 0.29)
            return [
                SlidingPiece(id: "big",   w: 2, h: 2, x: 1, y: 0, label: "Big block",     fill: big,  ink: .white),
                SlidingPiece(id: "tall1", w: 1, h: 2, x: 0, y: 1, label: "Tall block 1",  fill: tall, ink: .white),
                SlidingPiece(id: "tall2", w: 1, h: 2, x: 3, y: 1, label: "Tall block 2",  fill: tall, ink: .white),
                SlidingPiece(id: "tall3", w: 1, h: 2, x: 0, y: 3, label: "Tall block 3",  fill: tall, ink: .white),
                SlidingPiece(id: "tall4", w: 1, h: 2, x: 3, y: 3, label: "Tall block 4",  fill: tall, ink: .white),
                SlidingPiece(id: "wide",  w: 2, h: 1, x: 1, y: 3, label: "Wide block",    fill: wide, ink: .white),
                SlidingPiece(id: "unit1", w: 1, h: 1, x: 0, y: 0, label: "Small block 1", fill: unit, ink: .white),
                SlidingPiece(id: "unit2", w: 1, h: 1, x: 3, y: 0, label: "Small block 2", fill: unit, ink: .white),
                SlidingPiece(id: "unit3", w: 1, h: 1, x: 1, y: 2, label: "Small block 3", fill: unit, ink: .white),
                SlidingPiece(id: "unit4", w: 1, h: 1, x: 2, y: 2, label: "Small block 4", fill: unit, ink: .white),
            ]

        // 標準（古典の定番。華容道の橫刀立馬と同じ並び）。
        //  父 娘 娘 母
        //  父 娘 娘 母
        //  祖 番 番 祖
        //  祖 丁 丁 祖
        //  女 ・ ・ 女
        // 出口（下）を店先、上を奥と見立て、商売の丁稚を表に、家事の女中を奥に置く。
        // 標準だけは丁稚が女中より上にいる（丁稚は番頭に付いて商売を覚えるので、番頭のそば）。
        case .hakoiri:
            let shu     = Color(red: 0.75, green: 0.26, blue: 0.18)   // 娘（朱漆）
            let walnut  = Color(red: 0.60, green: 0.42, blue: 0.25)   // 縦駒（胡桃）
            let kaya    = Color(red: 0.79, green: 0.60, blue: 0.39)   // 横駒（榧）
            let hinoki  = Color(red: 0.89, green: 0.75, blue: 0.56)   // 小駒（檜）
            let gold    = Color(red: 0.93, green: 0.79, blue: 0.42)
            let woodInk = Color(red: 0.23, green: 0.14, blue: 0.08)
            let pale    = Color(red: 1.00, green: 0.96, blue: 0.89)
            return [
                SlidingPiece(id: "musume",  w: 2, h: 2, x: 1, y: 0, face: "娘",   ruby: "むすめ",     label: "むすめ",     fill: shu,    ink: gold),
                SlidingPiece(id: "chichi",  w: 1, h: 2, x: 0, y: 0, face: "父",   ruby: "ちち",       label: "ちち",       fill: walnut, ink: pale),
                SlidingPiece(id: "haha",    w: 1, h: 2, x: 3, y: 0, face: "母",   ruby: "はは",       label: "はは",       fill: walnut, ink: pale),
                SlidingPiece(id: "sofu",    w: 1, h: 2, x: 0, y: 2, face: "祖父", ruby: "そふ",       label: "そふ",       fill: walnut, ink: pale),
                SlidingPiece(id: "sobo",    w: 1, h: 2, x: 3, y: 2, face: "祖母", ruby: "そぼ",       label: "そぼ",       fill: walnut, ink: pale),
                SlidingPiece(id: "banto",   w: 2, h: 1, x: 1, y: 2, face: "番頭", ruby: "ばんとう",   label: "ばんとう",   fill: kaya,   ink: woodInk),
                SlidingPiece(id: "decchi1", w: 1, h: 1, x: 1, y: 3, face: "丁稚", ruby: "でっち",     label: "でっち",     fill: hinoki, ink: woodInk),
                SlidingPiece(id: "decchi2", w: 1, h: 1, x: 2, y: 3, face: "丁稚", ruby: "でっち",     label: "でっち",     fill: hinoki, ink: woodInk),
                SlidingPiece(id: "jochu1",  w: 1, h: 1, x: 0, y: 4, face: "女中", ruby: "じょちゅう", label: "じょちゅう", fill: hinoki, ink: woodInk),
                SlidingPiece(id: "jochu2",  w: 1, h: 1, x: 3, y: 4, face: "女中", ruby: "じょちゅう", label: "じょちゅう", fill: hinoki, ink: woodInk),
            ]

        // 橫刀立馬（最短81手）。名前を確かめられた唯一の布局。
        // 縦2マスの4人は形は同じだが、色を武将ごとに変える（三國演義から）。
        //   關羽 … 緑の衣   張飛 … 墨   趙雲 … 白銀   馬超 … 青   黃忠 … 土黄   曹操 … 朱に金文字
        // 注音（ㄅㄆㄇㄈ）は台湾の読み方の記号。まだ漢字を習っていない子でも駒の名前が読める。
        // 黃忠と馬超がこの場面に揃うのは物語の都合で、史実ではない（遊びの約束事として扱う）。
        case .huarongdao:
            let zhu    = Color(red: 0.70, green: 0.19, blue: 0.16)
            let green  = Color(red: 0.25, green: 0.48, blue: 0.32)
            let black  = Color(red: 0.23, green: 0.23, blue: 0.25)
            let silver = Color(red: 0.85, green: 0.85, blue: 0.83)
            let blue   = Color(red: 0.36, green: 0.50, blue: 0.66)
            let yellow = Color(red: 0.78, green: 0.60, blue: 0.24)
            let wood   = Color(red: 0.85, green: 0.73, blue: 0.55)
            let gold   = Color(red: 0.89, green: 0.73, blue: 0.42)
            let ink    = Color(red: 0.95, green: 0.91, blue: 0.83)
            let dark   = Color(red: 0.17, green: 0.17, blue: 0.19)
            return [
                SlidingPiece(id: "caocao",     w: 2, h: 2, x: 1, y: 0, face: "曹操", ruby: "ㄘㄠˊㄘㄠ",    label: "曹操", fill: zhu,    ink: gold),
                SlidingPiece(id: "zhangfei",   w: 1, h: 2, x: 0, y: 0, face: "張飛", ruby: "ㄓㄤㄈㄟ",      label: "張飛", fill: black,  ink: ink),
                SlidingPiece(id: "zhaoyun",    w: 1, h: 2, x: 3, y: 0, face: "趙雲", ruby: "ㄓㄠˋㄩㄣˊ",   label: "趙雲", fill: silver, ink: dark),
                SlidingPiece(id: "machao",     w: 1, h: 2, x: 0, y: 2, face: "馬超", ruby: "ㄇㄚˇㄔㄠ",     label: "馬超", fill: blue,   ink: ink),
                SlidingPiece(id: "huangzhong", w: 1, h: 2, x: 3, y: 2, face: "黃忠", ruby: "ㄏㄨㄤˊㄓㄨㄥ", label: "黃忠", fill: yellow, ink: Color(red: 0.17, green: 0.13, blue: 0.03)),
                SlidingPiece(id: "guanyu",     w: 2, h: 1, x: 1, y: 2, face: "關羽", ruby: "ㄍㄨㄢㄩˇ",     label: "關羽", fill: green,  ink: ink),
                SlidingPiece(id: "bing1",      w: 1, h: 1, x: 1, y: 3, face: "兵",   ruby: "ㄅㄧㄥ",        label: "兵",   fill: wood,   ink: Color(red: 0.23, green: 0.14, blue: 0.08)),
                SlidingPiece(id: "bing2",      w: 1, h: 1, x: 2, y: 3, face: "兵",   ruby: "ㄅㄧㄥ",        label: "兵",   fill: wood,   ink: Color(red: 0.23, green: 0.14, blue: 0.08)),
                SlidingPiece(id: "bing3",      w: 1, h: 1, x: 0, y: 4, face: "兵",   ruby: "ㄅㄧㄥ",        label: "兵",   fill: wood,   ink: Color(red: 0.23, green: 0.14, blue: 0.08)),
                SlidingPiece(id: "bing4",      w: 1, h: 1, x: 3, y: 4, face: "兵",   ruby: "ㄅㄧㄥ",        label: "兵",   fill: wood,   ink: Color(red: 0.23, green: 0.14, blue: 0.08)),
            ]
        }
    }

    // MARK: 記録

    /// 自己最少手数を保存するキー（小さいほどよい記録。ScoreBoard.timeKeys に入れてある）
    var bestKey: String {
        switch self {
        case .klotski:    return UDKey.klotskiBest
        case .hakoiri:    return UDKey.hakoiriBest
        case .huarongdao: return UDKey.huarongdaoBest
        }
    }

    /// クリアした回数を保存するキー（見せるだけの数字。何かを開く条件には使わない）
    var clearsKey: String {
        switch self {
        case .klotski:    return UDKey.klotskiClears
        case .hakoiri:    return UDKey.hakoiriClears
        case .huarongdao: return UDKey.huarongdaoClears
        }
    }

    /// タイトル画面のタイル
    var pickerSelection: GamePickerSelection {
        switch self {
        case .klotski:    return .klotski
        case .hakoiri:    return .hakoiri
        case .huarongdao: return .huarongdao
        }
    }
}
