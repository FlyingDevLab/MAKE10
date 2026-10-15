//
//  MemoryModels.swift
//  FDL-TenBlitz
//
//  Created by 空飛ぶ研究室(FlyingDevLab) on 2026/09/06.
//

// どうぶつめくり（神経衰弱）のデータ構造・定数・カード面の供給役をまとめたファイル。
//
// ★ このファイルの構成 ★
//   MemoryTuning        … 秒数・余白などの調整用定数を1か所に集めた入れ物
//   MemoryDeck          … あそぶカードの種類（どうぶつ 4×5 / どうぶつ 5×5 / せいざ / つき 2種）
//   MemoryItem          … カード1組ぶんの定義（絵柄・読み上げ・クリア後にえらべるシール）
//   MemoryAnimal        … 動物カードの定義（絵文字と読み上げラベル）
//   MemoryZodiac        … 星座カードの定義（♈〜♓ と読み上げラベル）
//   MemoryMonth         … 月カードの定義（英語・漢字・季節のシール）
//   CardFace            … カード表面の中身を表す型
//   CardFaceProvider    … カード面を供給する役割を決めたプロトコル（差し替え点）
//   DeckFaceProvider    … CardFaceProvider の実装。えらんだ種類のカードを返す
//   CardState           … カード1枚分の状態
//   MemoryPhase         … 盤面が今どの局面にいるか
//
// ★ なぜ「カード面を供給する役」を分けているのか ★
//   このゲームのロジック（MemoryGameEngine）は、カードを pairID という
//   ただの文字列でしか扱いません。ゾウなのか星座なのか、絵文字なのか文字なのかを
//   ロジックは一切知らないという作りにしてあります。
//
//   こうしておくと、カード面を別のもの（星座・月の名前など）に差し替えたいとき、
//   CardFaceProvider に渡す中身を変えるだけで済み、
//   めくる・判定する・クリアするといったロジックには一行も手を入れずに済みます。
//   （v1.6.0 で星座・月のカードを足したときも、エンジンのルールは変えていません）
//
// ★ 保存について ★
//   このゲームは盤面を一切保存しません。途中でやめた場合は盤面を捨て、
//   次に入ったときは新しくシャッフルし直します。
//   スコアも記録しないため、ScoreBoard.allScoreKeys にも登録しません。
//   保存するのは「前回えらんだカードの種類」だけです（UDKey.memoryDeck。端末の中だけ。iCloud には送らない）。
//
// ★ 「十二支」と書かない理由 ★
//   5×5 の動物は 🐁🐇🐅🐂🐉🐍🫏🐏🐒🐓🐕🐖 の12種ですが、画面・読み上げ・コメントのどこにも
//   特定の暦の名前は出しません。国によって入る動物が違う（たとえば日本では 🐖 の代わりにイノシシ）ため、
//   「12種の動物」としてだけ扱います。

import SwiftUI

// MARK: - MemoryTuning

// ★ なぜ定数を1か所に集めるのか ★
//   秒数や余白の数値がコードのあちこちに散らばっていると、
//   「めくりを少し速くしたい」と思ったときに探し回ることになります。
//   ここにまとめておけば、調整はこのブロックを見るだけで済みます。
//
// ★ case を持たない enum にしている理由 ★
//   インスタンスを作る必要がない「ただの入れ物」だからです。
//   MemoryTuning() と書けなくなるため、誤った使い方を防げます（ScoreBoard と同じ考え方）。

/// どうぶつめくりの調整用定数。秒数・寸法・見た目の数値をここに集約する。
enum MemoryTuning {

    // MARK: 盤面

    /// グリッドの列数。どの種類も5列固定（行の数は MemoryDeck.rows）。
    static let columns:    Int = 5      // ← 変更可

    /// 盤面の左右余白（pt）。
    static let boardPadding: CGFloat = 16   // ← 変更可

    /// カードどうしの隙間（pt）。
    static let cardSpacing:  CGFloat = 8    // ← 変更可

    // ★ 角丸半径について ★
    //   アプリ共通の DS.cardRadius は 22 ですが、あれは画面幅いっぱいの
    //   大きなカード用の値です。ここでのカードは1辺が65pt前後しかないため、
    //   22 を使うと辺の3分の1が丸くなり、四角ではなく丸に見えてしまいます。
    //   そのため共通トークンを使わず、専用の値を持たせています。

    /// カードの角丸半径（pt）。
    static let cardCornerRadius: CGFloat = 12   // ← 変更可

    // MARK: ごほうび

    /// むずかしい種類（せいざ・つき）を全部そろえたときの「むずかしさ ボーナス」（kcal）。
    /// 結果画面の内訳に「むずかしさ ボーナス」として出る（EnergyRewardBanner を参照）。
    static let hardClearBonus: Double = 100   // ← 変更可

    // MARK: 秒数

    /// カードをめくるアニメーションの長さ（秒）。表裏の入れ替えはこの半分の時点で行う。
    static let flipDuration:   TimeInterval = 0.25   // ← 変更可

    /// 一致したときの演出の長さ（秒）。
    static let matchHold:      TimeInterval = 0.35   // ← 変更可

    /// 不一致のとき、2枚を表向きのまま見せておく長さ（秒）。
    /// この時間を待たずに次のカードをタップすれば、待機は打ち切られる（先行入力）。
    static let mismatchHold:   TimeInterval = 0.80   // ← 変更可

    // ★ 最短表示時間とは ★
    //   2枚目が表になった直後のタップまで受け付けてしまうと、
    //   連打している子は「何がめくれたのか」を一度も見られないまま進んでしまい、
    //   覚えようがなくなります。
    //   そこで、めくってから最低この時間は伏せないというルールを設けます。
    //   この時間内に来たタップは捨てずに1件だけ覚えておき、時間が来たら実行します。

    /// 2枚目を表示してから、先行入力を受け付け始めるまでの最短時間（秒）。
    static let minRevealTime:  TimeInterval = 0.35   // ← 変更可

    /// クリア時、薄くなっていたカードを元の濃さに戻すアニメーションの長さ（秒）。
    static let clearRestore:   TimeInterval = 0.40   // ← 変更可

    /// クリア時、揃った盤面を見せておく長さ（秒）。この後に結果画面へ移る。
    static let clearBoardHold: TimeInterval = 1.20   // ← 変更可

    // ★ 誤タップ防止について ★
    //   このゲームは連打を前提に作られているため、クリア直後も指が動き続けています。
    //   結果画面が出た瞬間のタップで、中身を見る前にシールが決まってしまわないよう、
    //   表示から一定時間は入力を受け付けません。
    //   FinishedView・JankenResultView と同じ 1.0 秒に揃えています。

    /// 結果画面が表示されてから、シール選びのタップを受け付け始めるまでの時間（秒）。
    static let selectTapGuard: TimeInterval = 1.00   // ← 変更可

    // MARK: 見た目

    /// 一致済みカードの透明度。表向きのまま薄くして、残っているカードを目立たせる。
    static let matchedOpacity: Double = 0.55   // ← 変更可
}

// MARK: - MemoryDeck

// ★ 種類を enum にしている理由 ★
//   「何組あるか」「盤面は何行か」「中央にロゴを置くか」「むずかしさ ボーナスがあるか」など、
//   種類ごとに決まる値をここ1か所にまとめるためです。
//   種類を増やすときは case を1つ足し、下の switch を埋めるだけで済みます
//   （埋め忘れはコンパイルエラーになるので、漏れません）。
//
// ★ rawValue を保存に使う ★
//   前回えらんだ種類を UserDefaults に rawValue の文字列で保存します。
//   名前を変えると、前回の選択が読めなくなる（最初の種類に戻るだけで、害はない）。

/// あそぶカードの種類。スタート画面でえらぶ。
enum MemoryDeck: String, CaseIterable, Identifiable {
    case animals        // どうぶつ 10組（4×5）。いままでと同じ
    case animals12      // どうぶつ 12組（5×5・中央にロゴ）
    case zodiac         // せいざ 12組（5×5・中央にロゴ）
    case monthsEnglish  // つき（えいご） 12組（5×5・中央にロゴ）
    case monthsKanji    // つき（かんじ） 12組（5×5・中央にロゴ）

    var id: String { rawValue }

    /// このカードの種類で使う、カード1組ぶんの定義の一覧。
    var items: [MemoryItem] {
        switch self {
        case .animals:       return MemoryAnimal.classic.map(\.item)
        case .animals12:     return MemoryAnimal.twelve.map(\.item)
        case .zodiac:        return MemoryZodiac.allCases.map(\.item)
        case .monthsEnglish: return MemoryMonth.all.map(\.englishItem)
        case .monthsKanji:   return MemoryMonth.all.map(\.kanjiItem)
        }
    }

    /// ペアの数。
    var pairCount: Int {
        switch self {
        case .animals: return 10
        default:       return 12
        }
    }

    /// 盤面の行の数（列は MemoryTuning.columns の5列）。
    var rows: Int {
        switch self {
        case .animals: return 4
        default:       return 5
        }
    }

    // ★ 中央にロゴを置く理由 ★
    //   5×5 は25マスで、奇数なのでカードの組（2枚ずつ）では埋まりきらず、1マス余ります。
    //   その1マスを、いちばん目立つまん中に置き、Flying Dev Lab のロゴにしています。
    //   ロゴは押せない飾りなので、めくる・そろえるには関わりません。

    /// 盤面のまん中にロゴを置くか（マスの数がカードの枚数より1つ多いとき）。
    var hasCenterLogo: Bool { MemoryTuning.columns * rows > pairCount * 2 }

    /// むずかしい種類か。全部そろえると「むずかしさ ボーナス」がもらえる。
    var isHard: Bool {
        switch self {
        case .animals, .animals12:                   return false
        case .zodiac, .monthsEnglish, .monthsKanji:  return true
        }
    }

    /// スタート画面のボタンに大きく出す見本（その種類のカード1枚ぶん）。
    var preview: String {
        switch self {
        case .animals:       return "🐘"
        case .animals12:     return "🐉"
        case .zodiac:        return "♈"
        case .monthsEnglish: return "Jan"
        case .monthsKanji:   return "如月"
        }
    }

    /// スタート画面のボタンに出す名前（翻訳キー）。
    /// どうぶつは2種類とも同じ名前にして、盤面の大きさ（4×5 / 5×5）で見分けてもらう。
    var nameKey: LocalizedStringKey {
        switch self {
        case .animals, .animals12: return "memory_deck_animals"
        case .zodiac:              return "memory_deck_zodiac"
        case .monthsEnglish:       return "memory_deck_months_en"
        case .monthsKanji:         return "memory_deck_months_kanji"
        }
    }

    /// 盤面の大きさの表示（「4×5」など）。数字と記号だけなので、翻訳しない。
    var gridLabel: String { "\(rows)×\(MemoryTuning.columns)" }

    /// 前回えらんだ種類。はじめてのときや、読めないときは「どうぶつ 4×5」。
    static var lastPlayed: MemoryDeck {
        get {
            let raw = UserDefaults.standard.string(forKey: UDKey.memoryDeck) ?? ""
            return MemoryDeck(rawValue: raw) ?? .animals
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: UDKey.memoryDeck) }
    }
}

// MARK: - MemoryItem

// ★ カード1組ぶんを1つの型にまとめる理由 ★
//   動物・星座・月で、絵柄の作り方も読み上げの作り方もばらばらです。
//   それを「pairID・表面・読み上げ・シール」という同じ形にそろえておけば、
//   エンジンも画面も、どの種類かを気にせずに扱えます。

/// カード1組ぶんの定義。
struct MemoryItem {
    /// 一致判定に使う識別子（CardState.pairID になる）。
    let pairID: String
    /// カードの表面。
    let face: CardFace
    /// VoiceOver（画面読み上げ）用の名前。画面には出さない。
    let label: Text
    /// クリア後に「すきな シール」としてえらべる絵文字。
    let sticker: String
}

// MARK: - MemoryAnimal

// ★ 動物の選び方（4×5 の10種） ★
//   幼児が形だけで見分けられるよう、シルエットが明確に異なる10種を選んでいます。
//   イヌとオオカミのように紛らわしい組み合わせや、
//   イルカとクジラのように輪郭が近いものは意図的に避けました。
//   色も10色すべて別系統にしてあり、形を覚える前に色で掴めるようにしています。
//
// ★ 5×5 の12種 ★
//   横向きの全身の絵文字（🐁🐅🐂 など）で、色や形が似たものが多く、10種よりむずかしくなります。
//   ここにある絵文字は、クリア後のシールにもなるので StickerCatalog にも入れてあります。
//
// ★ rawValue が pairID になる ★
//   ロジック側はこの enum を知らず、rawValue の文字列（"elephant" など）だけを扱います。

/// 動物カードの定義。rawValue がそのまま pairID として使われる。
enum MemoryAnimal: String, CaseIterable {
    // 4×5 の10種
    case elephant
    case giraffe
    case lion
    case rabbit
    case penguin
    case turtle
    case octopus
    case whale
    case butterfly
    case monkey
    // 5×5 の12種（全身の絵文字）
    case mouseBody
    case rabbitBody
    case tigerBody
    case oxBody
    case dragonBody
    case snakeBody
    case donkeyBody
    case sheepBody
    case monkeyBody
    case roosterBody
    case dogBody
    case pigBody

    /// 4×5（10組）で使う動物。
    static let classic: [MemoryAnimal] = [
        .elephant, .giraffe, .lion, .rabbit, .penguin,
        .turtle, .octopus, .whale, .butterfly, .monkey,
    ]

    /// 5×5（12組）で使う動物。
    static let twelve: [MemoryAnimal] = [
        .mouseBody, .rabbitBody, .tigerBody, .oxBody, .dragonBody, .snakeBody,
        .donkeyBody, .sheepBody, .monkeyBody, .roosterBody, .dogBody, .pigBody,
    ]

    /// カード表面に表示する絵文字。
    var emoji: String {
        switch self {
        case .elephant:    return "🐘"
        case .giraffe:     return "🦒"
        case .lion:        return "🦁"
        case .rabbit:      return "🐰"
        case .penguin:     return "🐧"
        case .turtle:      return "🐢"
        case .octopus:     return "🐙"
        case .whale:       return "🐳"
        case .butterfly:   return "🦋"
        case .monkey:      return "🐵"
        case .mouseBody:   return "🐁"
        case .rabbitBody:  return "🐇"
        case .tigerBody:   return "🐅"
        case .oxBody:      return "🐂"
        case .dragonBody:  return "🐉"
        case .snakeBody:   return "🐍"
        case .donkeyBody:  return "🫏"
        case .sheepBody:   return "🐏"
        case .monkeyBody:  return "🐒"
        case .roosterBody: return "🐓"
        case .dogBody:     return "🐕"
        case .pigBody:     return "🐖"
        }
    }

    // ★ LocalizedStringKey とは？ ★
    //   Text() に渡すと Localizable.xcstrings から現在の言語の訳文を
    //   自動で引いてくれる「翻訳キー」型です。
    //   String ではなくこの型で返すことで、15言語対応が呼び出し側に自動で効きます。
    //
    // ★ なぜ画面には名前を出さないのか ★
    //   このアプリは字が読めない年齢の子も対象にしているため、
    //   カードにも選択画面にも動物の名前は表示しません。絵文字だけで通じるためです。
    //   ただし VoiceOver（画面読み上げ）を使う人には名前が必要なので、
    //   読み上げ用のラベルとしてだけ用意しています。
    //   （うさぎ・さる は、顔の絵文字と全身の絵文字で同じ名前を使う）

    /// VoiceOver 読み上げ用の名前（翻訳キー）。画面には表示しない。
    var accessibilityLabel: LocalizedStringKey {
        switch self {
        case .elephant:                return "memory_animal_elephant"
        case .giraffe:                 return "memory_animal_giraffe"
        case .lion:                    return "memory_animal_lion"
        case .rabbit, .rabbitBody:     return "memory_animal_rabbit"
        case .penguin:                 return "memory_animal_penguin"
        case .turtle:                  return "memory_animal_turtle"
        case .octopus:                 return "memory_animal_octopus"
        case .whale:                   return "memory_animal_whale"
        case .butterfly:               return "memory_animal_butterfly"
        case .monkey, .monkeyBody:     return "memory_animal_monkey"
        case .mouseBody:               return "memory_animal_mouse"
        case .tigerBody:               return "memory_animal_tiger"
        case .oxBody:                  return "memory_animal_ox"
        case .dragonBody:              return "memory_animal_dragon"
        case .snakeBody:               return "memory_animal_snake"
        case .donkeyBody:              return "memory_animal_donkey"
        case .sheepBody:               return "memory_animal_sheep"
        case .roosterBody:             return "memory_animal_rooster"
        case .dogBody:                 return "memory_animal_dog"
        case .pigBody:                 return "memory_animal_pig"
        }
    }

    /// カード1組ぶんの定義。動物の絵文字が、そのままクリア後のシールになる。
    var item: MemoryItem {
        MemoryItem(pairID: rawValue, face: .emoji(emoji), label: Text(accessibilityLabel), sticker: emoji)
    }
}

// MARK: - MemoryZodiac

// ★ 星座がむずかしい理由 ★
//   12種とも同じ色の四角に、形の似た記号が1つずつ入った絵文字です。
//   色で覚えられないので、記号の形だけで覚える必要があり、動物よりずっとむずかしくなります。

/// 星座カードの定義。並びは ♈（おひつじ座）から ♓（うお座）の順。
enum MemoryZodiac: String, CaseIterable {
    case aries, taurus, gemini, cancer, leo, virgo
    case libra, scorpio, sagittarius, capricorn, aquarius, pisces

    /// カード表面に表示する絵文字。
    var emoji: String {
        switch self {
        case .aries:       return "♈"
        case .taurus:      return "♉"
        case .gemini:      return "♊"
        case .cancer:      return "♋"
        case .leo:         return "♌"
        case .virgo:       return "♍"
        case .libra:       return "♎"
        case .scorpio:     return "♏"
        case .sagittarius: return "♐"
        case .capricorn:   return "♑"
        case .aquarius:    return "♒"
        case .pisces:      return "♓"
        }
    }

    /// VoiceOver 読み上げ用の名前（翻訳キー）。画面には表示しない。
    var accessibilityLabel: LocalizedStringKey {
        switch self {
        case .aries:       return "memory_zodiac_aries"
        case .taurus:      return "memory_zodiac_taurus"
        case .gemini:      return "memory_zodiac_gemini"
        case .cancer:      return "memory_zodiac_cancer"
        case .leo:         return "memory_zodiac_leo"
        case .virgo:       return "memory_zodiac_virgo"
        case .libra:       return "memory_zodiac_libra"
        case .scorpio:     return "memory_zodiac_scorpio"
        case .sagittarius: return "memory_zodiac_sagittarius"
        case .capricorn:   return "memory_zodiac_capricorn"
        case .aquarius:    return "memory_zodiac_aquarius"
        case .pisces:      return "memory_zodiac_pisces"
        }
    }

    /// カード1組ぶんの定義。pairID には "zodiac_" を付けて、ほかの種類と重ならないようにする。
    var item: MemoryItem {
        MemoryItem(pairID: "zodiac_" + rawValue, face: .emoji(emoji),
                   label: Text(accessibilityLabel), sticker: emoji)
    }
}

// MARK: - MemoryMonth

// ★ 月のカードは2種類 ★
//   えいご … January〜December の英単語。どの言語でも英語のまま出す
//   かんじ … 睦月〜師走（日本の昔の月の呼び名）。どの言語でも同じ漢字を出す
//   漢字が読めない人にも分かるよう、かんじ のカードには小さく月の数字（1〜12）も添える。
//
// ★ クリア後のシール ★
//   文字はシールにできないので、その月らしい季節の絵文字からえらんでもらう。
//   ここにある絵文字は StickerCatalog にも入れてある（片方を変えたら両方を揃えること）。

/// 月カードの定義（1月〜12月）。
struct MemoryMonth {
    /// 月の数字（1〜12）。
    let number: Int
    /// 英語の月の名前。
    let english: String
    /// 日本の昔の月の呼び名（漢字）。
    let kanji: String
    /// クリア後にえらべる、その月らしい季節の絵文字。
    let season: String

    /// 1月〜12月の一覧。
    static let all: [MemoryMonth] = [
        MemoryMonth(number: 1,  english: "January",   kanji: "睦月",   season: "🎍"),   // ← 変更可（シールの絵文字）
        MemoryMonth(number: 2,  english: "February",  kanji: "如月",   season: "⛄"),
        MemoryMonth(number: 3,  english: "March",     kanji: "弥生",   season: "🎎"),
        MemoryMonth(number: 4,  english: "April",     kanji: "卯月",   season: "🌸"),
        MemoryMonth(number: 5,  english: "May",       kanji: "皐月",   season: "🎏"),
        MemoryMonth(number: 6,  english: "June",      kanji: "水無月", season: "☔"),
        MemoryMonth(number: 7,  english: "July",      kanji: "文月",   season: "🎋"),
        MemoryMonth(number: 8,  english: "August",    kanji: "葉月",   season: "🍉"),
        MemoryMonth(number: 9,  english: "September", kanji: "長月",   season: "🎑"),
        MemoryMonth(number: 10, english: "October",   kanji: "神無月", season: "🎃"),
        MemoryMonth(number: 11, english: "November",  kanji: "霜月",   season: "🍁"),
        MemoryMonth(number: 12, english: "December",  kanji: "師走",   season: "🎄"),
    ]

    // ★ 月の名前を翻訳ファイルに書かない理由 ★
    //   「1月」「January」「Janvier」… は、iOS が言語ごとに持っている暦の名前を使えば
    //   15言語ぶんを自分で訳さずに済みます（DateFormatter の standaloneMonthSymbols）。
    //   アプリの表示言語（端末の言語とちがうこともある）に合わせて読ませます。

    /// アプリの表示言語での月の名前（読み上げと、季節のシールの名前に使う）。
    var localizedName: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: Bundle.main.preferredLocalizations.first ?? "en")
        let symbols = formatter.standaloneMonthSymbols ?? []
        return symbols.indices.contains(number - 1) ? symbols[number - 1] : "\(number)"
    }

    /// えいご のカード1組ぶん。読み上げは、カードに書いてある英単語そのもの。
    var englishItem: MemoryItem {
        MemoryItem(pairID: "month_en_\(number)", face: .text(english, number: nil),
                   label: Text(verbatim: english), sticker: season)
    }

    /// かんじ のカード1組ぶん。読み上げは「睦月, 1月」のように、漢字とアプリの言語での月の名前。
    var kanjiItem: MemoryItem {
        MemoryItem(pairID: "month_kanji_\(number)", face: .text(kanji, number: number),
                   label: Text(verbatim: "\(kanji), \(localizedName)"), sticker: season)
    }
}

// MARK: - CardFace

// ★ なぜ enum にするのか ★
//   カード表面の中身は、絵文字のこともあれば文字や画像のこともあり得ます。
//   String に決め打ちしてしまうと、後から別の種類を扱えなくなります。
//   enum にしておけば「どれかである」ことを型で表現でき、
//   描画側は switch で漏れなく分岐できます（網羅漏れはコンパイルエラーになります）。

/// カード表面の中身。
enum CardFace {
    /// 絵文字1文字。
    case emoji(String)

    /// 文字（月の名前など）。number があれば、すみに小さく数字を添える（漢字が読めない人のため）。
    case text(String, number: Int?)

    /// 画像。現時点では使用していないが、カード面を差し替える余地を型で示すために残す。
    case image(UIImage)
}

// MARK: - CardFaceProvider

/// カード面を供給する役割。ロジック層はこのプロトコル越しにしかカード面を知らない。
protocol CardFaceProvider {

    /// 使用するペアの識別子を返す。呼ばれるたびに並びが変わってよい。
    func pairIdentifiers() -> [String]

    /// pairID に対応するカード表面を返す。
    func face(for pairID: String) -> CardFace

    /// pairID に対応する VoiceOver 用ラベルを返す。
    func accessibilityLabel(for pairID: String) -> Text
}

// MARK: - DeckFaceProvider

/// えらんだ種類（MemoryDeck）のカードを供給する CardFaceProvider の実装。
struct DeckFaceProvider: CardFaceProvider {

    /// pairID からカード1組ぶんの定義を引くための辞書。
    private let itemsByID: [String: MemoryItem]

    init(deck: MemoryDeck) {
        itemsByID = Dictionary(uniqueKeysWithValues: deck.items.map { ($0.pairID, $0) })
    }

    /// その種類のペアの識別子を、シャッフルして返す。
    func pairIdentifiers() -> [String] {
        itemsByID.keys.shuffled()
    }

    // ★ 未知の識別子が来たときについて ★
    //   ここで nil や強制アンラップを使うと、想定外の値でクラッシュします。
    //   代わりに「？」を返して、盤面は壊さずに見た目だけで異常が分かるようにしています。

    /// 識別子に対応するカード表面を返す。未知の識別子には「？」を返してクラッシュを避ける。
    func face(for pairID: String) -> CardFace {
        itemsByID[pairID]?.face ?? .emoji("❓")
    }

    /// 識別子に対応する読み上げラベルを返す。
    func accessibilityLabel(for pairID: String) -> Text {
        itemsByID[pairID]?.label ?? Text("memory_card_face_down")
    }
}

// MARK: - CardState

// ★ id と pairID の違い ★
//   id      … カード1枚を指す固有の番号。同じ動物のカード2枚は別の id を持つ。
//   pairID  … 一致判定に使う識別子。同じ動物のカード2枚は同じ pairID を持つ。
//   タップの対象を指すときは id を、揃ったかどうかを見るときは pairID を使います。
//
// ★ なぜ配列の添字ではなく id で扱うのか ★
//   添字（0番目、1番目…）を持ち回ると、配列が変化したときに
//   別のカードを指してしまったり、範囲外アクセスでクラッシュしたりします。
//   id で引いて guard で受ける形にしておけば、対象が消えていても安全に何もせず終われます。

/// カード1枚分の状態。
struct CardState: Identifiable {

    /// カード1枚を指す固有の番号。
    let id = UUID()

    /// 一致判定に使う識別子。同じ絵柄の2枚が同じ値を持つ。
    let pairID: String

    /// 表向きかどうか。
    var isFaceUp: Bool = false

    /// 揃って確定済みかどうか。確定したカードは以後タップを受け付けない。
    var isMatched: Bool = false
}

// MARK: - MemoryPhase

// ★ 局面を型で持つ理由 ★
//   「1枚めくった状態」「2枚めくって判定中」といった状況を、
//   bool 変数の組み合わせで表そうとすると、ありえない組み合わせが作れてしまいます
//   （1枚もめくっていないのに判定中、など）。
//   enum にしておけば、盤面は必ずこの4つのどれか1つになり、矛盾した状態が作れません。

/// 盤面が今どの局面にいるか。
enum MemoryPhase: Equatable {

    /// 入力待ち。1枚もめくられていない。
    case idle

    /// 1枚目をめくった状態。関連値はめくったカードの id。
    case oneUp(UUID)

    /// 2枚目をめくり、一致・不一致の処理を待っている状態。
    case judging(first: UUID, second: UUID)

    /// 全ペアが揃った状態。
    case cleared
}

// MARK: - MemoryReward

/// そろえた1組ぶんのごほうび。View が「+◯」を浮かべるために使う。
/// 同じ量が続いても毎回別のものとして扱えるよう、id を持たせている。
struct MemoryReward: Identifiable, Equatable {
    let id = UUID()
    /// もらったエネルギー（kcal）
    let kcal: Double
    /// そのときの連続数（1 = 連続なし）
    let combo: Int
}
