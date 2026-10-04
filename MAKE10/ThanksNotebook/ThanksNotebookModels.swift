//
//  ThanksNotebookModels.swift
//  FDL-TenBlitz
//
//  Created by 空飛ぶ研究室(FlyingDevLab) on 2026/10/04.
//
//  ありがとう てちょう の「中身」の定義。ミッション・相手・ごほうびの量・1日分のページ。
//  仕様は docs/SPEC_thanks_notebook.md を参照。
//
//  ★ このファイルの構成 ★
//    ThanksTuning    … ごほうびの量など、調整する数値（ここだけ触ればOK）
//    ThanksCategory  … ミッションの分類（ありがとう／ことば・やさしさ／じぶんのこと）
//    ThanksMission   … ミッション1つ（絵文字・文・分類・相手を選ぶか）
//    ThanksPerson    … 「だれに？」の相手
//    ThanksDayPage   … 1日分のページ（その日の3つのミッションと、チェックした相手）

import SwiftUI

// MARK: - ⚙️ 調整パラメータ

enum ThanksTuning {
    /// 1日に並ぶミッションの数。
    static let missionsPerDay = 3   // ⚠️ 変更注意: 下の選び方（ThanksDayPage.slotRules）と数を合わせること

    /// その日にチェックした数ごとの「その日の合計」ごほうび（kcal）。
    /// [0個, 1個, 2個, 3個（全部）]。チェックが増えたときに、差分だけ渡す。
    static let rewardTotals: [Double] = [0, 10, 30, 100]   // ← 変更可
}

// MARK: - ThanksCategory

/// ミッションの分類。日替わりの選び方に使う。
enum ThanksCategory: String, Codable, CaseIterable {
    case thanks     // 🙏 ありがとう
    case kindness   // 👋 ことば・やさしさ
    case myself     // 🧹 じぶんのこと
}

// MARK: - ThanksMission

// ★ rawValue を保存に使っている ★
//   ページには rawValue（"thanksSomeone" など）で保存している。並び替えや追加は自由だが、
//   ⚠️ 変更注意: 一度出した case の rawValue を変えたり、case を消したりすると、保存済みの手帳が読めなくなる。
//   ミッションをやめたいときは case を残したまま、日替わりの候補から外す（ThanksDayPage.pick の filter）。

/// ミッション1つ。文は Localizable.xcstrings の "thanks_mission_<rawValue>" に入っている。
enum ThanksMission: String, Codable, CodingKeyRepresentable, CaseIterable, Identifiable {
    // 🙏 ありがとう
    case thanksSomeone      // だれかに「ありがとう」を いおう
    case thanksCook         // ごはんを つくってくれた ひとに「ありがとう」を いおう
    case thanksHappy        // うれしかった ことに「ありがとう」を いおう
    case thanksHelper       // おせわに なった ひとに「ありがとう」を いおう
    case thanksLetter       // 「ありがとう」の きもちを えや てがみに かこう
    case thanksBeThanked    // 「ありがとう」って いってもらえる ことを しよう
    case thanksThreeTimes   // きょう「ありがとう」を 3かい いおう
    case thanksMeal         // 「いただきます」「ごちそうさま」で たべものに ありがとう
    case thanksThings       // だいじな ものに「ありがとう」を いおう
    case thanksMyself       // じぶんに「ありがとう」「がんばったね」を いおう
    // 👋 ことば・やさしさ
    case greet              // だれかに あいさつを しよう
    case goodMorning        // 「おはよう」を いおう
    case goodNight          // 「おやすみ」を いおう
    case talkFun            // きょう たのしかった ことを だれかに はなそう
    case helpOut            // だれかの おてつだいを しよう
    case makeSmile          // だれかを えがおに しよう
    case listen             // だれかの おはなしを さいごまで きこう
    case praise             // だれかに「すごいね」を いおう
    // 🧹 じぶんのこと
    case tidyUp             // つかった ものを かたづけよう
    case brushTeeth         // はみがきを しよう
    case dressSelf          // じぶんで きがえを しよう
    case readBook           // ほんを よもう

    var id: String { rawValue }

    var emoji: String {
        switch self {
        case .thanksSomeone:    return "🙏"
        case .thanksCook:       return "🍚"
        case .thanksHappy:      return "🎁"
        case .thanksHelper:     return "🤗"
        case .thanksLetter:     return "💌"
        case .thanksBeThanked:  return "🔁"
        case .thanksThreeTimes: return "🎵"
        case .thanksMeal:       return "🍽️"
        case .thanksThings:     return "🧸"
        case .thanksMyself:     return "🌱"
        case .greet:            return "👋"
        case .goodMorning:      return "🌞"
        case .goodNight:        return "🌙"
        case .talkFun:          return "💬"
        case .helpOut:          return "🤝"
        case .makeSmile:        return "😊"
        case .listen:           return "👂"
        case .praise:           return "✨"
        case .tidyUp:           return "🧹"
        case .brushTeeth:       return "🪥"
        case .dressSelf:        return "👕"
        case .readBook:         return "📚"
        }
    }

    var category: ThanksCategory {
        switch self {
        case .thanksSomeone, .thanksCook, .thanksHappy, .thanksHelper, .thanksLetter,
             .thanksBeThanked, .thanksThreeTimes, .thanksMeal, .thanksThings, .thanksMyself:
            return .thanks
        case .greet, .goodMorning, .goodNight, .talkFun, .helpOut, .makeSmile, .listen, .praise:
            return .kindness
        case .tidyUp, .brushTeeth, .dressSelf, .readBook:
            return .myself
        }
    }

    /// チェックするときに「だれに？」を選ぶか。
    var asksWho: Bool {
        switch self {
        case .thanksMeal, .thanksMyself,
             .tidyUp, .brushTeeth, .dressSelf, .readBook:
            return false
        default:
            return true
        }
    }

    /// ミッションの文の翻訳キー。
    /// ⚠️ 変更注意: LocalizedStringKey("thanks_mission_\(rawValue)") と文字列補間で書くと、
    ///   キーが "thanks_mission_%@" になって訳が引けない。いったん String にしてから渡すこと。
    var titleKey: LocalizedStringKey { LocalizedStringKey("thanks_mission_" + rawValue) }
}

// MARK: - ThanksPerson

/// 「だれに？」の相手。いろいろな家庭の形があるので「おうちの ひと」も用意している。
/// 保存は rawValue。一度出した rawValue を変えたり case を消したりしないこと（ThanksMission と同じ理由）。
/// 宣言の順がそのまま選ぶカードの並びになる。
///
/// ★ 入れていない相手 ★
///   「すきな ひと」（恋愛の意味にとられて冷やかしの種になりやすい）と
///   「きらいな ひと」（人に「きらい」の名前をつけることになり、手帳の目的と反対）は、あえて入れていない。
///   苦手な人へのあいさつなどは「ほかの ひと」で受け止める（docs/SPEC_thanks_notebook.md を参照）。
enum ThanksPerson: String, Codable, CaseIterable, Identifiable {
    case father, mother, family, grandpa, grandma, sibling, friend, teacher
    case nonHuman   // どうぶつ・ぬいぐるみ・しょくぶつ（人以外の友達。ペットがいない子も選べる）
    case other
    case me         // じぶん（何でも「じぶん」で済ませないよう、いちばん最後に並べる）

    var id: String { rawValue }

    var emoji: String {
        switch self {
        case .father:   return "👨"
        case .mother:   return "👩"
        case .family:   return "🏠"
        case .grandpa:  return "👴"
        case .grandma:  return "👵"
        case .sibling:  return "👦"
        case .friend:   return "🧒"
        case .teacher:  return "🧑‍🏫"
        case .nonHuman: return "🐶🧸🌱"
        case .other:    return "🙂"
        case .me:       return "🙋"
        }
    }

    /// 相手の名前の翻訳キー。
    /// ⚠️ 文字列補間を使わない理由は ThanksMission.titleKey を参照。
    var nameKey: LocalizedStringKey { LocalizedStringKey("thanks_person_" + rawValue) }
}

// MARK: - ThanksDayPage

/// 1日分のページ。その日のミッションと、チェックしたミッションの相手を持つ。
struct ThanksDayPage: Codable, Equatable {
    /// その日のミッション（並び順どおり）。
    var missions: [ThanksMission]
    /// チェックしたミッションと、その相手。キーがあればチェック済み（相手を選ばないミッションは空の配列）。
    var checks: [ThanksMission: [ThanksPerson]]
    /// その日にごほうびを渡し終えた段階（= これまでで一番多かったチェック数）。
    /// チェックを外して付け直しても、二重にごほうびを渡さないために覚えておく。
    var rewardedStage: Int

    /// チェックした数。
    var checkedCount: Int { missions.filter { checks[$0] != nil }.count }

    /// ぜんぶチェックしたか。
    var isComplete: Bool { !missions.isEmpty && checkedCount == missions.count }

    func isChecked(_ mission: ThanksMission) -> Bool { checks[mission] != nil }

    // MARK: 日替わりの選び方

    /// 何個目の枠に、どの分類から選ぶか。
    ///   1個目: 🙏 ありがとう から必ず
    ///   2個目: 👋 ことば・やさしさ から
    ///   3個目: 残り全部（ありがとうを含む）から
    /// こうすると毎日少なくとも1個は「ありがとう」が入り、2個入る日も多くなる。
    static let slotRules: [[ThanksCategory]] = [
        [.thanks],
        [.kindness],
        ThanksCategory.allCases,
    ]

    /// 新しい日のページを作る。
    static func makeNew() -> ThanksDayPage {
        var page = ThanksDayPage(missions: [], checks: [:], rewardedStage: 0)
        for rule in slotRules {
            if let pick = pick(from: rule, excluding: page.missions) {
                page.missions.append(pick)
            }
        }
        return page
    }

    /// まだチェックしていないミッションだけを入れ替える（引き直し）。
    /// チェック済みは残すので、引き直してもごほうびを何度ももらうことはできない。
    mutating func reroll() {
        for index in missions.indices where !isChecked(missions[index]) {
            let rule = Self.slotRules.indices.contains(index) ? Self.slotRules[index] : ThanksCategory.allCases
            // 今あるミッション（入れ替える本人も含む）は除いて選ぶので、必ず別のものに変わる
            if let pick = Self.pick(from: rule, excluding: missions) {
                missions[index] = pick
            }
        }
    }

    /// 指定の分類から、excluding に無いミッションを1つ選ぶ。候補が無ければ nil。
    private static func pick(from categories: [ThanksCategory], excluding: [ThanksMission]) -> ThanksMission? {
        ThanksMission.allCases
            .filter { categories.contains($0.category) && !excluding.contains($0) }
            .randomElement()
    }
}

// MARK: - ThanksDayPage の読み込み

// ★ 知らないミッション・相手を読み飛ばす理由 ★
//   ふつうの読み込みでは、保存データの中に1つでも知らない名前（将来ミッションや相手を
//   減らしたり名前を変えたりしたときの古い名前）があると、手帳ぜんぶが読めなくなってしまう。
//   名前をいったん文字列として読み、知っているものだけ残すことで、ほかの記録は守る。
//   書き出し（Encodable）はいつもどおり自動で作られる形のまま。
extension ThanksDayPage {
    private enum CodingKeys: String, CodingKey {
        case missions, checks, rewardedStage
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let missionNames = try container.decode([String].self, forKey: .missions)
        let checkNames   = try container.decode([String: [String]].self, forKey: .checks)

        missions = missionNames.compactMap(ThanksMission.init(rawValue:))
        checks   = [:]
        for (missionName, personNames) in checkNames {
            guard let mission = ThanksMission(rawValue: missionName) else { continue }
            checks[mission] = personNames.compactMap(ThanksPerson.init(rawValue:))
        }
        rewardedStage = try container.decode(Int.self, forKey: .rewardedStage)
    }
}
