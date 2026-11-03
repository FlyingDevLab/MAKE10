//
//  RiverCrossingModels.swift
//  FDL-TenBlitz
//
//  Created by 空飛ぶ研究室(FlyingDevLab) on 2026/11/03.
//

// 川わたりパズルで使うデータ型と、4つのステージの表を定義するファイル。
// ルール（舟に乗せてよいか・岸に残してよいか）もステージの表に持たせている。
// ViewModel は RiverCrossingViewModel.swift に分離している。
//
// ★ このファイルの構成 ★
//   RiverSide       … 駒の居場所（こちら岸・むこう岸・舟の上）
//   RiverActor      … 駒1つ分（どうぶつ・ひと・キャベツ）
//   RiverMessage    … 画面の下に出す一言（「ふねは いっぱいだよ」など）
//   RiverStage      … 4つのステージ（駒・舟の席・こげる人・ルール）
//   RiverArt        … 駒と舟の絵（あれば使う。無ければ絵文字）
//
// ★ Web 版と同じルール ★
//   flyingdevlab.com/kids/river-crossing/ の game.js と同じステージ・同じ判定にしている。
//   最短の回数（7 / 9 / 11 / 17）は、幅優先探索で全状態を調べて確かめた値。
//   判定は「渡り終えた後の両岸」だけを見る。舟の上の組み合わせは見ない
//   （舟の上は一瞬であり、そこまで咎めると こどもには理不尽に見えるため）。

import SwiftUI

// MARK: - 居場所

/// 駒の居場所。
enum RiverSide: Equatable {
    case near   // こちら岸（はじめにいる岸）
    case far    // むこう岸（全員を運ぶ先）
    case boat   // 舟の上

    /// 反対の岸。舟が渡るときに使う（.boat の反対は無いので自分を返す）。
    var opposite: RiverSide {
        switch self {
        case .near: return .far
        case .far:  return .near
        case .boat: return .boat
        }
    }
}

// MARK: - 駒

/// 駒1つ分。id はステージの中だけで重ならなければよい。
struct RiverActor: Identifiable, Equatable {

    /// 役。駒の色分けと、ルールの判定に使う。
    enum Kind: Equatable {
        case person     // せんどう
        case beast      // おおかみ・やぎ
        case thing      // キャベツ
        case adult      // おとな・おとうさん・おかあさん・せんせい
        case kid        // こども（ステージ2）
        case parent     // おやぐま など（ステージ3）
        case child      // こぐま など（ステージ3）
        case son        // むすこ（ステージ4）
        case daughter   // むすめ（ステージ4）
        case dog        // いぬ（ステージ4）
    }

    let id:     String
    let emoji:  String
    /// 絵のファイル名（拡張子なし）。MAKE10/Images/ の .webp と同じ名前。
    let art:    String
    let kind:   Kind
    /// 名前の翻訳キー。同じ名前の駒が2つ以上いることがある（おとな・むすこ など）。
    let nameKey: String
    /// こどもの駒だけ、自分の親の id（ステージ3の判定に使う）。
    var parent: String? = nil

    /// 画面とVoiceOverに出す名前。
    var name: LocalizedStringKey { LocalizedStringKey(nameKey) }
}

// MARK: - 一言

/// 画面の下に出す一言。ルール違反のときの「何が起きかけたか」と、操作できない理由。
///
/// ★ 文言をここにまとめている理由 ★
///   ステージの表に文言を直接書くと、同じ文言（「ふねは いっぱいだよ」など）が
///   あちこちに散らばる。ここにまとめれば、翻訳キーの一覧もこの switch だけで済む。
enum RiverMessage: Equatable {
    case boatFull          // 席が足りない
    case noRower           // 舟に乗っている中に、こげる人がいない
    case wolfGoat          // おおかみと やぎ
    case goatCabbage       // やぎと キャベツ
    case grownUpWithKid    // おとなと こどもは いっしょに のれない
    case oneGrownUp        // おとなは ひとりまで
    case shy(String)       // こどもが よその おやを こわがる（中身は こどもの名前の翻訳キー）
    case dogBarks          // いぬが ほえる
    case dadDaughter       // おとうさんと むすめ
    case momSon            // おかあさんと むすこ

    var text: LocalizedStringKey {
        switch self {
        case .boatFull:       return "river_msg_boat_full"
        case .noRower:        return "river_msg_no_rower"
        case .wolfGoat:       return "river_msg_wolf_goat"
        case .goatCabbage:    return "river_msg_goat_cabbage"
        case .grownUpWithKid: return "river_msg_grownup_with_kid"
        case .oneGrownUp:     return "river_msg_one_grownup"
        case .dogBarks:       return "river_msg_dog_barks"
        case .dadDaughter:    return "river_msg_dad_daughter"
        case .momSon:         return "river_msg_mom_son"
        // こどもの名前を差し込む形にすると、言語によって語順や助詞が合わなくなるので、3つを別の文にしている
        case .shy(let childKey):
            switch childKey {
            case "river_actor_cub":   return "river_msg_shy_cub"
            case "river_actor_bunny": return "river_msg_shy_bunny"
            default:                  return "river_msg_shy_kitten"
            }
        }
    }
}

// MARK: - ステージ

/// 4つのステージ。rawValue はベスト記録のキーと「最後に選んだステージ」の保存に使うので変えないこと。
enum RiverStage: String, CaseIterable, Identifiable {
    case wolf     // おおかみと やぎと キャベツ（最短7回）
    case weight   // おとなと こども（最短9回）
    case pairs    // 3くみの おやこ（最短11回）
    case raft     // 8にんの いかだ（最短17回）

    var id: String { rawValue }

    /// 正式な名前（決まりごとの見出しに出す）
    var title: LocalizedStringKey {
        switch self {
        case .wolf:   return "river_stage_wolf"
        case .weight: return "river_stage_weight"
        case .pairs:  return "river_stage_pairs"
        case .raft:   return "river_stage_raft"
        }
    }

    /// ステージ選択のボタンに出す短い名前。4つを横に並べるので正式な名前は入り切らない。
    var shortTitle: LocalizedStringKey {
        switch self {
        case .wolf:   return "river_stage_wolf_short"
        case .weight: return "river_stage_weight_short"
        case .pairs:  return "river_stage_pairs_short"
        case .raft:   return "river_stage_raft_short"
        }
    }

    /// ステージ選択のボタンに出す駒（その駒の絵か絵文字を使う）
    var iconActor: RiverActor {
        switch self {
        case .wolf:   return actors[1]   // おおかみ
        case .weight: return actors[2]   // こども
        case .pairs:  return actors[0]   // おやぐま
        case .raft:   return actors[7]   // いぬ
        }
    }

    /// 最短の回数（幅優先探索で確かめた値。このファイル冒頭を参照）
    var par: Int {
        switch self {
        case .wolf:   return 7
        case .weight: return 9
        case .pairs:  return 11
        case .raft:   return 17
        }
    }

    /// 舟に乗れる人数
    var seats: Int { 2 }

    /// こげる駒の id。nil なら だれでも こげる。
    var rowers: Set<String>? {
        switch self {
        case .wolf:          return ["boatman"]
        case .weight, .pairs: return nil
        case .raft:          return ["dad", "mom", "teacher"]
        }
    }

    /// そのステージの決まりごと（画面に箇条書きで出す）
    var rules: [LocalizedStringKey] {
        switch self {
        case .wolf:
            return ["river_rule_wolf_1", "river_rule_wolf_2", "river_rule_wolf_3"]
        case .weight:
            return ["river_rule_weight_1", "river_rule_weight_2"]
        case .pairs:
            return ["river_rule_pairs_1", "river_rule_pairs_2", "river_rule_pairs_3"]
        case .raft:
            return ["river_rule_raft_1", "river_rule_raft_2", "river_rule_raft_3", "river_rule_raft_4"]
        }
    }

    // ★ ステージ3を「だれでも こげる」にしている理由 ★
    //   古くは「嫉妬深い夫」として知られる問題を親子に置き換えたもの。
    //   漕げる人を親だけに絞ると解が無くなる（総当たりで確かめた）ため、こどもも漕げることにした。
    // ★ ステージ4に「せんせいと いぬ」がいる理由 ★
    //   原型は「警官と泥棒」を含む形だが、こども向けなので置き換えてある。手数は変わらない。
    var actors: [RiverActor] {
        switch self {
        case .wolf:
            return [
                RiverActor(id: "boatman", emoji: "🧑", art: "boatman", kind: .person, nameKey: "river_actor_boatman"),
                RiverActor(id: "wolf",    emoji: "🐺", art: "wolf",    kind: .beast,  nameKey: "river_actor_wolf"),
                RiverActor(id: "goat",    emoji: "🐐", art: "goat",    kind: .beast,  nameKey: "river_actor_goat"),
                RiverActor(id: "cabbage", emoji: "🥬", art: "cabbage", kind: .thing,  nameKey: "river_actor_cabbage"),
            ]
        case .weight:
            return [
                RiverActor(id: "adult1", emoji: "👨", art: "man",   kind: .adult, nameKey: "river_actor_grownup"),
                RiverActor(id: "adult2", emoji: "👩", art: "woman", kind: .adult, nameKey: "river_actor_grownup"),
                RiverActor(id: "kid1",   emoji: "👦", art: "boy",   kind: .kid,   nameKey: "river_actor_kid"),
                RiverActor(id: "kid2",   emoji: "👧", art: "girl",  kind: .kid,   nameKey: "river_actor_kid"),
            ]
        case .pairs:
            return [
                RiverActor(id: "bearP",   emoji: "🐻", art: "bear-parent",   kind: .parent, nameKey: "river_actor_bear"),
                RiverActor(id: "bearC",   emoji: "🐻", art: "bear-child",    kind: .child,  nameKey: "river_actor_cub",    parent: "bearP"),
                RiverActor(id: "rabbitP", emoji: "🐰", art: "rabbit-parent", kind: .parent, nameKey: "river_actor_rabbit"),
                RiverActor(id: "rabbitC", emoji: "🐰", art: "rabbit-child",  kind: .child,  nameKey: "river_actor_bunny",  parent: "rabbitP"),
                RiverActor(id: "catP",    emoji: "🐱", art: "cat-parent",    kind: .parent, nameKey: "river_actor_cat"),
                RiverActor(id: "catC",    emoji: "🐱", art: "cat-child",     kind: .child,  nameKey: "river_actor_kitten", parent: "catP"),
            ]
        case .raft:
            return [
                RiverActor(id: "dad",     emoji: "👨",     art: "man",     kind: .adult,    nameKey: "river_actor_dad"),
                RiverActor(id: "mom",     emoji: "👩",     art: "woman",   kind: .adult,    nameKey: "river_actor_mom"),
                RiverActor(id: "boy1",    emoji: "👦",     art: "boy",     kind: .son,      nameKey: "river_actor_son"),
                RiverActor(id: "boy2",    emoji: "👦",     art: "boy",     kind: .son,      nameKey: "river_actor_son"),
                RiverActor(id: "girl1",   emoji: "👧",     art: "girl",    kind: .daughter, nameKey: "river_actor_daughter"),
                RiverActor(id: "girl2",   emoji: "👧",     art: "girl",    kind: .daughter, nameKey: "river_actor_daughter"),
                RiverActor(id: "teacher", emoji: "🧑‍🏫", art: "teacher", kind: .adult,    nameKey: "river_actor_teacher"),
                RiverActor(id: "dog",     emoji: "🐕",     art: "dog",     kind: .dog,      nameKey: "river_actor_dog"),
            ]
        }
    }

    /// 舟に乗せてよいかを見る。駄目なら理由を返す（席の数は ViewModel が別に見る）。
    func boardingProblem(crew: Set<String>) -> RiverMessage? {
        guard self == .weight else { return nil }
        let adults = actors.filter { $0.kind == .adult && crew.contains($0.id) }.count
        if adults > 0 && adults < crew.count { return .grownUpWithKid }
        if adults > 1 { return .oneGrownUp }
        return nil
    }

    /// その岸に残してよいかを見る。駄目なら理由を返す。
    func bankProblem(_ bank: Set<String>) -> RiverMessage? {
        switch self {
        case .wolf:
            if bank.contains("boatman") { return nil }
            if bank.contains("wolf") && bank.contains("goat") { return .wolfGoat }
            if bank.contains("goat") && bank.contains("cabbage") { return .goatCabbage }
            return nil

        case .weight:
            return nil   // 危ない組み合わせが1つも無いステージ。壁は舟の重さだけ

        case .pairs:
            // 自分の親がいない岸に、よその親といっしょに残すと こわがる
            for child in actors where child.kind == .child && bank.contains(child.id) {
                guard let parent = child.parent, !bank.contains(parent) else { continue }
                let otherParentHere = actors.contains {
                    $0.kind == .parent && $0.id != parent && bank.contains($0.id)
                }
                if otherParentHere { return .shy(child.nameKey) }
            }
            return nil

        case .raft:
            let has = { (kind: RiverActor.Kind) in
                actors.contains { $0.kind == kind && bank.contains($0.id) }
            }
            if bank.contains("dog") && !bank.contains("teacher") && bank.count > 1 { return .dogBarks }
            if bank.contains("dad") && !bank.contains("mom") && has(.daughter) { return .dadDaughter }
            if bank.contains("mom") && !bank.contains("dad") && has(.son) { return .momSon }
            return nil
        }
    }
}

// MARK: - 絵

/// 駒と舟の絵。MAKE10/Images/ に .webp があれば使い、無ければ nil を返す（呼び出し側は絵文字に戻す）。
///
/// ★ 絵が無くても遊べるようにしている理由 ★
///   Images/ はフリー素材で再配布できないため、.gitignore で除外している。
///   リポジトリをクローンした人の手元には絵が無いが、それでもゲームは成り立つ
///   （Web 版の /images/river-crossing/ と同じ考え方）。
///
/// ★ 一度読んだ絵を覚えておく理由 ★
///   駒は盤を描き直すたびに作り直すので、そのたびにファイルを読むと無駄が多い。
///   読めなかった名前も覚えておき、何度も探しに行かないようにしている。
enum RiverArt {
    @MainActor private static var cache: [String: UIImage?] = [:]

    @MainActor static func image(_ name: String) -> UIImage? {
        if let hit = cache[name] { return hit }
        let image = Bundle.main.url(forResource: name, withExtension: "webp")
            .flatMap { UIImage(contentsOfFile: $0.path) }
        cache[name] = image
        return image
    }

    /// 舟の絵
    @MainActor static var boat: UIImage? { image("boat") }
}
