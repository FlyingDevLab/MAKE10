//
//  GamePickerComponents.swift
//  FDL-TenBlitz
//
//  Created by 空飛ぶ研究室(FlyingDevLab) on 2026/03/08.
//

// タイトル画面のゲーム選択グリッドで使用する共有コンポーネント群。
// MakeTenContentView と TitleView の両方から参照するため、
// private ではなく internal アクセスレベルで定義している。
//
// ★ このファイルの構成 ★
//   GamePickerSelection … 選択可能な全ゲームの列挙型（MAKE10 モードも含む）
//   GameRankManager    … 並び順を UserDefaults に永続化するクラス
//   GamePickerTile     … タップ・フリック両対応のゲームタイルView
//
// 役割分担:
//   - GamePickerTile はジェスチャの「判定」までを担当し、
//     フリック時の吹き飛びアニメーションと並べ替えの「処理」は TitleView 側が行う。

import SwiftUI

// MARK: - GamePickerSelection

// ★ 新しいゲームを追加するには ★
//   ① ここに case を1つ追加する
//   ② icon / label / color の switch に分岐を追加する
//      （switch が全 case を網羅しているか Swift コンパイラがチェックするため、
//        追加し忘れるとコンパイルエラーになり、漏れが構造的に起きない）
//   ③ label の翻訳キーを Localizable.xcstrings に15言語分追加する
//   ④ スコアを持つゲームなら ScoreBoard.swift の allScoreKeys にもキーを追加する
//   CaseIterable に準拠しているため、case を追加するだけで
//   allCases（ゲーム一覧）と GameRankManager の並び順管理に自動的に含まれる。
//
// ⚠️ 変更注意: logoCard はゲームではなく「ブランドタイル」という特別枠。
//   タップでゲームを起動せず（GamePickerTile 側で明示的に無視）、
//   見た目も画面幅いっぱいのバナーとして TitleView 側で特別扱いする。
//   新しいゲームを追加する際にこの特別扱いと混同しないこと。

enum GamePickerSelection: String, CaseIterable, Hashable {
    case logoCard       // ブランドタイル（FDLロゴ＋回転リング。タップ無効・バナー表示）
    case normal         // MAKE10 30びょうモード
    case blitz          // MAKE10 10びょうモード（解放後のみ表示）
    case quiz
    case whackAMole
    case maze
    // ★ シールやさん・ガチャをここ（宣言の途中）に置いている理由 ★
    //   保存済みの並び順が無い新規インストールでは、宣言順がそのまま初期の並びになる。
    //   ロゴの下に2枚ずつ並ぶので、ここに置くと「下から2番目の段」に入り、
    //   入れ替わらない段で最初から目に入る（一番下の段は自動デモで入れ替わる）。
    //   既存ユーザーは保存データに無い case として先頭に入る（GameRankManager.init を参照）。
    case stickerShop    // シールやさん（エネルギーでシールを買う）
    case gacha          // ガチャ（エネルギーでシールを引く）
    // 新規インストールではシールやさん・ガチャの次の段に入る。既存ユーザーは先頭に入る（上の解説を参照）
    case thanksNotebook // ありがとう てちょう（毎日のミッション）
    case pinball
    case coinDrop
    case janken
    case tenPuzzle      // 四則演算テンパズル
    case memory         // どうぶつめくり（神経衰弱）
    case stickerStorage // シール管理・遊ぶ画面
    case stickerDex     // シールじてん（v1.6.0 から。シール帳・シールやさんからも開ける）

    /// タイルに表示する絵文字アイコン。
    /// ⚠️ logoCard は GamePickerTile 側で専用描画（ロゴ画像＋リング）に差し替わるため、
    ///   ここでの値は実際には表示されない（将来の参照用に定義だけ残す）。
    var icon: String {
        switch self {
        case .logoCard:         return "🌀"
        case .normal:           return "🔟"
        case .blitz:            return "⚡"
        case .quiz:             return "🗺️"
        case .whackAMole:       return "🔨"
        case .maze:             return "🧀"
        case .pinball:          return "🎱"
        case .coinDrop:         return "💰"
        case .janken:           return "✊"
        case .tenPuzzle:        return "🔢"
        case .memory:           return "🐘"
        case .stickerStorage:   return "🖼️"
        case .stickerDex:       return "📖"
        case .stickerShop:      return "🛍️"
        case .gacha:            return "🎁"
        case .thanksNotebook:   return "📒"
        }
    }

    // ★ LocalizedStringKey とは？ ★
    //   Text() に渡すと Localizable.xcstrings から現在の言語の訳文を
    //   自動で引いてくれる「翻訳キー」型です。
    //   String ではなくこの型で返すことで、15言語対応が呼び出し側に自動で効きます。

    /// タイルに表示するゲーム名の翻訳キー。
    /// logoCard はブランド名（固有名詞）のため翻訳せず、そのまま表示する。
    var label: LocalizedStringKey {
        switch self {
        case .logoCard:          return "Flying Dev Lab"
        case .normal:            return "title_mode_normal_label"
        case .blitz:             return "title_mode_blitz_label"
        case .quiz:              return "quiz_home_title"
        case .whackAMole:        return "whack_a_mole_title"
        case .maze:              return "maze_title"
        case .pinball:           return "pinball_title"
        case .coinDrop:          return "coindrop_title"
        case .janken:            return "janken_title"
        case .tenPuzzle:         return "tenpuzzle_title"
        case .memory:            return "memory_title"
        case .stickerStorage:    return "sticker_storage_title"
        case .stickerDex:        return "sticker_dex_title"
        case .stickerShop:       return "shop_title"
        case .gacha:             return "gacha_title"
        case .thanksNotebook:    return "thanks_notebook_title"
        }
    }

    /// タイルのテーマカラー（アイコン下のラベルと背景の薄塗りに使用）。
    var color: Color {
        switch self {
        case .logoCard:         return DS.muted
        case .normal:           return DS.primary
        case .blitz:            return DS.blitzColor
        case .quiz:             return .purple
        case .whackAMole:       return .orange
        case .maze:             return .green
        case .pinball:          return .red
        case .coinDrop:         return DS.gold
        case .janken:           return .teal
        case .tenPuzzle:        return .indigo
        case .memory:           return .brown
        case .stickerStorage:   return .pink
        case .stickerDex:       return .cyan
        case .stickerShop:      return DS.energy
        case .gacha:            return .mint
        case .thanksNotebook:   return Color(red: 0.80, green: 0.55, blue: 0.05)   // 📒 の黄色に合わせた山吹色
        }
    }
}

// MARK: - GameRankManager

// @Observable の解説は AppSettings.swift 冒頭を参照。

/// ゲームタイルの並び順を保持し、UserDefaults に永続化するクラス。
/// 並び順は「ゲームID → 順位」の辞書としてJSON形式で保存される。
@Observable
final class GameRankManager {

    /// 並び順の保存キー。"_v2" は保存形式のバージョン番号で、
    /// 形式を変えたときに数字を上げると旧データを安全に捨てて作り直せる。
    /// ※ このキーはこのクラスでしか使わないためここに置いているが、
    ///    UDKey enum（MakeTenModels.swift）への集約は将来のリファクタ候補。
    private static let udKey = "gamePickerRanks_v2"

    /// 現在の並び順のゲーム一覧。タイトル画面のグリッドはこの順に描画される。
    var sortedGames: [GamePickerSelection]

    // ★ Codable（JSONEncoder / JSONDecoder）とは？ ★
    //   Swift の値とJSONデータを相互変換する仕組みです。
    //   [String: Int] のような辞書はそのまま UserDefaults に入らないため、
    //   いったん JSON の Data に変換（エンコード）してから保存し、
    //   読み込み時に逆変換（デコード）します。
    //
    // ★ try? とは？ ★
    //   エラーを投げる処理を「失敗したら nil」に変換する書き方です。
    //   ここでは保存データが壊れていてもクラッシュさせず、
    //   if let が不成立 → デフォルト順（定義順）にフォールバックします。

    /// 保存済みの並び順があれば復元し、なければ定義順で初期化する。
    /// ⚠️ 既存ユーザーの保存データに無い新しい case（新ゲーム追加時など）は、
    ///   自動的に先頭（ロゴが先頭ならロゴのすぐ後ろ）へ入る。複数同時追加時は宣言順のまま1つのブロックになる。
    init() {
        sortedGames = Self.loadSaved()
    }

    /// 保存済みの並び順を読み直す。自動デモで見た目だけ動かした並びを捨てたいときに呼ぶ。
    func reloadSaved() {
        sortedGames = Self.loadSaved()
    }

    /// 保存済みの並び順を読み込む。保存が無ければ定義順を返す。
    private static func loadSaved() -> [GamePickerSelection] {
        let all = GamePickerSelection.allCases
        if let data = UserDefaults.standard.data(forKey: udKey),
           let dict = try? JSONDecoder().decode([String: Int].self, from: data) {
            // 辞書に無いゲーム（保存後に追加された新ゲーム）は先頭に入れて、すぐ目に入るようにする。
            // 複数を同時に追加した場合は enum の宣言順のまま先頭ブロックになる。
            let known    = all.filter { dict[$0.rawValue] != nil }
                              .sorted { dict[$0.rawValue]! < dict[$1.rawValue]! }
            let newGames = all.filter { dict[$0.rawValue] == nil }
            // ★ ロゴが先頭のときは、ロゴのすぐ後ろに入れる ★
            //   ロゴより前に新しいタイルが1枚だけ入ると、ロゴ（画面幅いっぱいの段）の手前で
            //   その1枚だけの段になり、右側がぽっかり空いてしまうため。
            if known.first == .logoCard {
                return [.logoCard] + newGames + known.dropFirst()
            }
            return newGames + known
        }
        return all
    }

    /// 指定ゲームを並び順の最後尾へ移動する（フリックで吹き飛ばしたときに呼ばれる）。
    /// - Parameter persist: 保存するか。自動デモでは false にして、見た目だけ動かす
    ///   （ユーザーが自分で並べた順番を、デモが勝手に書き換えないようにするため）。
    func throwToBottom(_ game: GamePickerSelection, persist: Bool = true) {
        sortedGames.removeAll { $0 == game }
        sortedGames.append(game)
        if persist { save() }
    }

    /// i 番目と j 番目のタイルを入れ替える。
    /// 範囲外の添字は guard で弾き、何もしない（クラッシュ防止）。
    /// - Parameter persist: 保存するか。自動デモでは false にして、見た目だけ動かす。
    func swap(at i: Int, with j: Int, persist: Bool = true) {
        guard i >= 0, j >= 0, i < sortedGames.count, j < sortedGames.count else { return }
        sortedGames.swapAt(i, j)
        if persist { save() }
    }

    /// バナー（単独行）を上下フリックしたときの3点ローテーション方向。
    enum RotateDirection {
        case down   // バナーが相手の行より後ろへ移動する（＝相手の行が繰り上がる）
        case up     // バナーが相手の行より前へ移動する（＝相手の行が繰り下がる）
    }

    /// バナーと、隣接する2枚組の行をまるごと入れ替える（3点ローテーション）。
    /// 通常の swap（2点交換）と違い、「1個」対「複数個」を丸ごと前後させる操作のため専用に用意している。
    /// - Parameters:
    ///   - bannerIndex: sortedGames内でのバナーの現在位置
    ///   - rowIndices:  入れ替え相手の行を構成するゲームの sortedGames内インデックス（1〜2個）
    ///   - direction:   .down ならバナーが相手の行より後ろへ、.up なら前へ移動する
    func rotateBanner(at bannerIndex: Int, withRow rowIndices: [Int], direction: RotateDirection) {
        guard sortedGames.indices.contains(bannerIndex) else { return }
        guard !rowIndices.isEmpty, rowIndices.allSatisfy({ sortedGames.indices.contains($0) }) else { return }

        let banner   = sortedGames[bannerIndex]
        let rowGames = rowIndices.map { sortedGames[$0] }   // インデックスがずれる前に値で保持しておく

        sortedGames.remove(at: bannerIndex)

        // 削除後、後続の要素が1つずつ詰まっているため位置を値から引き直す
        let newRowIndices = rowGames.compactMap { sortedGames.firstIndex(of: $0) }
        guard !newRowIndices.isEmpty else { return }

        switch direction {
        case .down:
            sortedGames.insert(banner, at: (newRowIndices.max() ?? 0) + 1)
        case .up:
            sortedGames.insert(banner, at: newRowIndices.min() ?? 0)
        }

        save()
    }

    /// 現在の並び順を「ゲームID → 順位」の辞書に変換してUserDefaultsへ保存する。
    private func save() {
        var dict: [String: Int] = [:]
        for (index, game) in sortedGames.enumerated() {
            dict[game.rawValue] = index
        }
        if let data = try? JSONEncoder().encode(dict) {
            UserDefaults.standard.set(data, forKey: Self.udKey)
        }
    }
}

// MARK: - GamePickerTile

/// ゲーム選択グリッドの1タイル。タップ（ゲーム起動）とフリック（並べ替え）の両方に反応する。
/// logoCard のみ例外で、タップは無反応（フリックは他タイルと同じ、または TitleView 側の特別処理に委ねる）。
struct GamePickerTile: View {

    // MARK: 設定項目（呼び出し側から渡すパラメータ）

    /// 表示するゲーム。
    let game:      GamePickerSelection
    /// フリックで吹き飛ぶ演出中のオフセット。TitleView 側がアニメーションで更新する。
    let flyOffset: CGSize
    /// タップ確定時に呼ばれる（ゲーム起動）。logoCard では呼ばれない。
    let onTap:     () -> Void
    /// フリック確定時に移動量と速度を渡して呼ばれる（並べ替え処理は TitleView 側）。
    let onFlick:   (_ translation: CGSize, _ velocity: CGSize) -> Void

    /// 指の移動距離がこの値（pt）未満なら「タップ」、以上なら「フリック」と判定する。
    private let tapDistanceThreshold: CGFloat = 15   // ← 変更可

    // MARK: ローカル状態

    /// 押下中フラグ。押している間だけタイルを縮小表示する（logoCard では立てない＝押し込み演出なし）。
    @State private var isPressed = false

    /// logoCard 専用：リング回転角度（度）。表示中ずっと左回転し続ける。
    @State private var ringAngle: Double = 0

    // MARK: body

    var body: some View {
        VStack(spacing: 6) {
            // アイコン部分。logoCard だけ絵文字・ラベルを出さず、ロゴ画像＋回転リングのみを大きく表示する。
            if game == .logoCard {
                ZStack {
                    Image("fdl-logo-mark")
                        .resizable()
                        .scaledToFit()
                        .padding(7)   // ← 変更可（リングとの隙間。小さいほどロゴ本体が大きくなる）
                    Image("fdl-logo-ring")
                        .resizable()
                        .scaledToFit()
                        // blendMode(.multiply): リング画像の白背景を透過させる
                        // （TitleView の旧アニメーションカードと同じ手法）
                        .blendMode(.multiply)
                        .rotationEffect(.degrees(ringAngle))
                        .onAppear {
                            withAnimation(
                                .linear(duration: 11)   // ← 変更可（回転速度・秒/周）
                                .repeatForever(autoreverses: false)
                            ) { ringAngle = -360 }      // 負値 = 左回転
                        }
                }
                // カードの余白いっぱいまでロゴを拡大する（他タイルと違い縦横とも可変域を使い切る）
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                // ラベルを表示しない代わりに、VoiceOver 用にブランド名を読み上げさせる
                .accessibilityLabel(game.label)
            } else {
                Text(game.icon).font(.largeTitle)
                Text(game.label)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(game.color)
            }
        }
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)   // 行内の最大高さまで背景を伸ばす
        // かべがみの上でも透けないよう tintFill で塗る（DesignSystem の tintFill を参照）
        .background(
            RoundedRectangle(cornerRadius: DS.tagRadius)
                .tintFill(game == .logoCard ? DS.card : game.color.opacity(0.1))
        )
        // 押下中は少し縮めて「押している感」を出す（吹き飛び演出中は縮小しない）
        .scaleEffect(isPressed && flyOffset == .zero ? 0.94 : 1.0)   // ← 変更可（押下時の縮小率）
        .offset(flyOffset)
        .animation(.easeInOut(duration: 0.1), value: isPressed)
        // ★ タップとフリックを1つのジェスチャで判定する理由 ★
        //   onTapGesture と DragGesture を別々に付けると競合して
        //   どちらかが反応しなくなることがあります。
        //   そこで minimumDistance: 0 の DragGesture 1つだけで全タッチを受け取り、
        //   指を離した時点の移動距離で「タップかフリックか」を自分で判定しています。
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    // logoCard は押し込み演出も出さない（タップしても何も起きないため）
                    if !isPressed && game != .logoCard { isPressed = true }
                }
                .onEnded { value in
                    isPressed = false
                    // 三平方の定理で始点から終点までの直線距離を求める
                    let t        = value.translation
                    let distance = sqrt(t.width * t.width + t.height * t.height)
                    if distance < tapDistanceThreshold {
                        // logoCard はブランドタイルでありゲームではないため、タップは無視する
                        guard game != .logoCard else { return }
                        SoundManager.shared.vibrate()
                        SoundManager.shared.playTap()
                        onTap()
                    } else {
                        onFlick(value.translation, value.velocity)
                    }
                }
        )
    }
}
