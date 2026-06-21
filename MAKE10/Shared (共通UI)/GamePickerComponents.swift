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

enum GamePickerSelection: String, CaseIterable, Hashable {
    case normal         // MAKE10 30びょうモード
    case blitz          // MAKE10 10びょうモード（解放後のみ表示）
    case quiz
    case whackAMole
    case maze
    case pinball
    case coinDrop
    case janken
    case stickerStorage // シール管理・遊ぶ画面

    /// タイルに表示する絵文字アイコン。
    var icon: String {
        switch self {
        case .normal:          return "🔟"
        case .blitz:           return "⚡"
        case .quiz:            return "🗺️"
        case .whackAMole:      return "🔨"
        case .maze:            return "🧀"
        case .pinball:         return "🎱"
        case .coinDrop:        return "💰"
        case .janken:          return "✊"
        case .stickerStorage:  return "🖼️"
        }
    }

    // ★ LocalizedStringKey とは？ ★
    //   Text() に渡すと Localizable.xcstrings から現在の言語の訳文を
    //   自動で引いてくれる「翻訳キー」型です。
    //   String ではなくこの型で返すことで、15言語対応が呼び出し側に自動で効きます。

    /// タイルに表示するゲーム名の翻訳キー。
    var label: LocalizedStringKey {
        switch self {
        case .normal:          return "title_mode_normal_label"
        case .blitz:           return "title_mode_blitz_label"
        case .quiz:            return "quiz_home_title"
        case .whackAMole:      return "whack_a_mole_title"
        case .maze:            return "maze_title"
        case .pinball:         return "pinball_title"
        case .coinDrop:        return "coindrop_title"
        case .janken:          return "janken_title"
        case .stickerStorage:  return "sticker_storage_title"
        }
    }

    /// タイルのテーマカラー（アイコン下のラベルと背景の薄塗りに使用）。
    var color: Color {
        switch self {
        case .normal:          return DS.primary
        case .blitz:           return DS.blitzColor
        case .quiz:            return .purple
        case .whackAMole:      return .orange
        case .maze:            return .green
        case .pinball:         return .red
        case .coinDrop:        return DS.gold
        case .janken:          return .teal
        case .stickerStorage:  return .pink
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
    init() {
        let all = GamePickerSelection.allCases
        if let data = UserDefaults.standard.data(forKey: Self.udKey),
           let dict = try? JSONDecoder().decode([String: Int].self, from: data) {
            // ?? 999: 辞書に無いゲーム（保存後に追加された新ゲーム）は末尾に回す
            sortedGames = all.sorted { (dict[$0.rawValue] ?? 999) < (dict[$1.rawValue] ?? 999) }
        } else {
            sortedGames = all
        }
    }

    /// 指定ゲームを並び順の最後尾へ移動して保存する（フリックで吹き飛ばしたときに呼ばれる）。
    func throwToBottom(_ game: GamePickerSelection) {
        sortedGames.removeAll { $0 == game }
        sortedGames.append(game)
        save()
    }

    /// i 番目と j 番目のタイルを入れ替えて保存する。
    /// 範囲外の添字は guard で弾き、何もしない（クラッシュ防止）。
    func swap(at i: Int, with j: Int) {
        guard i >= 0, j >= 0, i < sortedGames.count, j < sortedGames.count else { return }
        sortedGames.swapAt(i, j)
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
struct GamePickerTile: View {

    // MARK: 設定項目（呼び出し側から渡すパラメータ）

    /// 表示するゲーム。
    let game:      GamePickerSelection
    /// フリックで吹き飛ぶ演出中のオフセット。TitleView 側がアニメーションで更新する。
    let flyOffset: CGSize
    /// タップ確定時に呼ばれる（ゲーム起動）。
    let onTap:     () -> Void
    /// フリック確定時に移動量と速度を渡して呼ばれる（並べ替え処理は TitleView 側）。
    let onFlick:   (_ translation: CGSize, _ velocity: CGSize) -> Void

    /// 指の移動距離がこの値（pt）未満なら「タップ」、以上なら「フリック」と判定する。
    private let tapDistanceThreshold: CGFloat = 15   // ← 変更可

    // MARK: ローカル状態

    /// 押下中フラグ。押している間だけタイルを縮小表示する。
    @State private var isPressed = false

    // MARK: body

    var body: some View {
        VStack(spacing: 6) {
            Text(game.icon).font(.largeTitle)
            Text(game.label)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(game.color)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(
            game.color.opacity(0.1),
            in: RoundedRectangle(cornerRadius: DS.tagRadius)
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
                    if !isPressed { isPressed = true }
                }
                .onEnded { value in
                    isPressed = false
                    // 三平方の定理で始点から終点までの直線距離を求める
                    let t        = value.translation
                    let distance = sqrt(t.width * t.width + t.height * t.height)
                    if distance < tapDistanceThreshold {
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
