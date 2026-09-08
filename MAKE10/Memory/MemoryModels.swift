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
//   MemoryAnimal        … カード面に使う動物10種の定義（絵文字と読み上げラベル）
//   CardFace            … カード表面の中身を表す型
//   CardFaceProvider    … カード面を供給する役割を決めたプロトコル（差し替え点）
//   AnimalFaceProvider  … CardFaceProvider の実装。動物絵文字を返す
//   CardState           … カード1枚分の状態
//   MemoryPhase         … 盤面が今どの局面にいるか
//
// ★ なぜ「カード面を供給する役」を分けているのか ★
//   このゲームのロジック（MemoryGameEngine）は、カードを pairID という
//   ただの文字列でしか扱いません。ゾウなのかキリンなのか、絵文字なのか写真なのかを
//   ロジックは一切知らないという作りにしてあります。
//
//   こうしておくと、カード面を別のもの（例えば自分で撮った写真）に差し替えたいとき、
//   CardFaceProvider を実装した別の型を用意するだけで済み、
//   めくる・判定する・クリアするといったロジックには一行も手を入れずに済みます。
//
//   実装が今は1つしかないためプロトコルが大げさに見えますが、
//   「ここが差し替え点である」ことを型で示しておくことに意味があります。
//
// ★ 保存について ★
//   このゲームは盤面を一切保存しません。UserDefaults のキー（UDKey）も追加しません。
//   途中でやめた場合は盤面を捨て、次に入ったときは新しくシャッフルし直します。
//   スコアも記録しないため、ScoreBoard.allScoreKeys にも登録しません。

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

    /// グリッドの列数。5列固定。
    static let columns:    Int = 5      // ← 変更可

    /// ペアの数。10ペア = カード20枚（5列 × 4行）。
    static let pairCount:  Int = 10     // ← 変更可

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

    /// クリア時、揃った盤面を見せておく長さ（秒）。この後にシール選択画面へ移る。
    static let clearBoardHold: TimeInterval = 1.20   // ← 変更可

    // ★ 誤タップ防止について ★
    //   このゲームは連打を前提に作られているため、クリア直後も指が動き続けています。
    //   シール選択画面が出た瞬間のタップで中身を見る前に決まってしまわないよう、
    //   表示から一定時間は入力を受け付けません。
    //   FinishedView・JankenResultView と同じ 1.0 秒に揃えています。

    /// シール選択画面が表示されてから、タップを受け付け始めるまでの時間（秒）。
    static let selectTapGuard: TimeInterval = 1.00   // ← 変更可

    // MARK: 見た目

    /// 一致済みカードの透明度。表向きのまま薄くして、残っているカードを目立たせる。
    static let matchedOpacity: Double = 0.55   // ← 変更可
}

// MARK: - MemoryAnimal

// ★ 動物の選び方 ★
//   幼児が形だけで見分けられるよう、シルエットが明確に異なる10種を選んでいます。
//   イヌとオオカミのように紛らわしい組み合わせや、
//   イルカとクジラのように輪郭が近いものは意図的に避けました。
//   色も10色すべて別系統にしてあり、形を覚える前に色で掴めるようにしています。
//
// ★ rawValue が pairID になる ★
//   ロジック側はこの enum を知らず、rawValue の文字列（"elephant" など）だけを扱います。
//   文字列にしておくことで、将来カード面を写真に差し替えたときも
//   同じ仕組み（識別子で一致を判定する）がそのまま使えます。

/// カード面に使う動物10種。rawValue がそのまま pairID として使われる。
enum MemoryAnimal: String, CaseIterable {
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

    /// カード表面に表示する絵文字。
    var emoji: String {
        switch self {
        case .elephant:  return "🐘"
        case .giraffe:   return "🦒"
        case .lion:      return "🦁"
        case .rabbit:    return "🐰"
        case .penguin:   return "🐧"
        case .turtle:    return "🐢"
        case .octopus:   return "🐙"
        case .whale:     return "🐳"
        case .butterfly: return "🦋"
        case .monkey:    return "🐵"
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

    /// VoiceOver 読み上げ用の名前（翻訳キー）。画面には表示しない。
    var accessibilityLabel: LocalizedStringKey {
        switch self {
        case .elephant:  return "memory_animal_elephant"
        case .giraffe:   return "memory_animal_giraffe"
        case .lion:      return "memory_animal_lion"
        case .rabbit:    return "memory_animal_rabbit"
        case .penguin:   return "memory_animal_penguin"
        case .turtle:    return "memory_animal_turtle"
        case .octopus:   return "memory_animal_octopus"
        case .whale:     return "memory_animal_whale"
        case .butterfly: return "memory_animal_butterfly"
        case .monkey:    return "memory_animal_monkey"
        }
    }
}

// MARK: - CardFace

// ★ なぜ enum にするのか ★
//   カード表面の中身は、絵文字のこともあれば画像のこともあり得ます。
//   String に決め打ちしてしまうと、後から画像を扱えなくなります。
//   enum にしておけば「どちらかである」ことを型で表現でき、
//   描画側は switch で漏れなく分岐できます（網羅漏れはコンパイルエラーになります）。

/// カード表面の中身。
enum CardFace {
    /// 絵文字1文字。
    case emoji(String)

    /// 画像。現時点では使用していないが、カード面を差し替える余地を型で示すために残す。
    case image(UIImage)
}

// MARK: - CardFaceProvider

/// カード面を供給する役割。ロジック層はこのプロトコル越しにしかカード面を知らない。
protocol CardFaceProvider {

    /// 使用するペアの識別子を count 個返す。呼ばれるたびに並びが変わってよい。
    func pairIdentifiers(count: Int) -> [String]

    /// pairID に対応するカード表面を返す。
    func face(for pairID: String) -> CardFace

    /// pairID に対応する VoiceOver 用ラベルを返す。
    func accessibilityLabel(for pairID: String) -> LocalizedStringKey
}

// MARK: - AnimalFaceProvider

/// 動物絵文字をカード面として供給する CardFaceProvider の実装。
struct AnimalFaceProvider: CardFaceProvider {

    /// 動物10種をシャッフルして先頭 count 個の識別子を返す。
    /// 現在は count が常に10（全種使用）だが、枚数を変えられる形にしてある。
    func pairIdentifiers(count: Int) -> [String] {
        MemoryAnimal.allCases
            .shuffled()
            .prefix(count)
            .map { $0.rawValue }
    }

    // ★ 未知の識別子が来たときについて ★
    //   ここで nil や強制アンラップを使うと、想定外の値でクラッシュします。
    //   代わりに「？」を返して、盤面は壊さずに見た目だけで異常が分かるようにしています。

    /// 識別子に対応する絵文字を返す。未知の識別子には「？」を返してクラッシュを避ける。
    func face(for pairID: String) -> CardFace {
        guard let animal = MemoryAnimal(rawValue: pairID) else { return .emoji("❓") }
        return .emoji(animal.emoji)
    }

    /// 識別子に対応する読み上げラベルを返す。
    func accessibilityLabel(for pairID: String) -> LocalizedStringKey {
        guard let animal = MemoryAnimal(rawValue: pairID) else { return "memory_card_face_down" }
        return animal.accessibilityLabel
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
