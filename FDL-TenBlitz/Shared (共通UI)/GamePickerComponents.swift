//
//  GamePickerComponents.swift
//  FDL-TenBlitz
//
//  Created by 空飛ぶ研究室(FlyingDevLab) on 2026/06/02.
//

// タイトル画面のゲーム選択グリッドで使用する共有コンポーネント群。
// MakeTenContentView と TitleView の両方から参照するため、
// private ではなく internal アクセスレベルで定義している。
//
// ★ このファイルの構成 ★
//   GamePickerSelection … 選択可能な全ゲームの列挙型（MAKE10 モードも含む）
//   GameRankManager    … 並び順を UserDefaults に永続化するクラス
//   GamePickerTile     … タップ・フリック両対応のゲームタイルView

import SwiftUI

// MARK: - GamePickerSelection

enum GamePickerSelection: String, CaseIterable, Hashable {
    case normal     // MAKE10 30びょうモード
    case blitz      // MAKE10 10びょうモード（解放後のみ表示）
    case quiz
    case whackAMole
    case maze
    case pinball
    case coinDrop
    case janken

    var icon: String {
        switch self {
        case .normal:     return "⏱️"
        case .blitz:      return "⚡"
        case .quiz:       return "🎯"
        case .whackAMole: return "🔨"
        case .maze:       return "🗺️"
        case .pinball:    return "🎱"
        case .coinDrop:   return "💰"
        case .janken:     return "✊"
        }
    }

    var label: LocalizedStringKey {
        switch self {
        case .normal:     return "title_mode_normal_label"
        case .blitz:      return "title_mode_blitz_label"
        case .quiz:       return "Quiz"
        case .whackAMole: return "Whack-a-Mole"
        case .maze:       return "Maze"
        case .pinball:    return "Pinball"
        case .coinDrop:   return "CoinDrop"
        case .janken:     return "janken_title"
        }
    }

    var color: Color {
        switch self {
        case .normal:     return DS.primary
        case .blitz:      return DS.blitzColor
        case .quiz:       return .purple
        case .whackAMole: return .orange
        case .maze:       return .green
        case .pinball:    return .red
        case .coinDrop:   return DS.gold
        case .janken:     return .teal
        }
    }
}

// MARK: - GameRankManager

@Observable
final class GameRankManager {

    private static let udKey = "gamePickerRanks_v2"

    var sortedGames: [GamePickerSelection]

    init() {
        let all = GamePickerSelection.allCases
        if let data = UserDefaults.standard.data(forKey: Self.udKey),
           let dict = try? JSONDecoder().decode([String: Int].self, from: data) {
            sortedGames = all.sorted { (dict[$0.rawValue] ?? 999) < (dict[$1.rawValue] ?? 999) }
        } else {
            sortedGames = all
        }
    }

    func throwToBottom(_ game: GamePickerSelection) {
        sortedGames.removeAll { $0 == game }
        sortedGames.append(game)
        save()
    }

    func swap(at i: Int, with j: Int) {
        guard i >= 0, j >= 0, i < sortedGames.count, j < sortedGames.count else { return }
        sortedGames.swapAt(i, j)
        save()
    }

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
//
// ゲーム選択グリッドの1つのタイル。
// タップとフリックを1つの DragGesture で判別する。
//
// ★ flyOffset について ★
//   末尾送り演出でタイルをフリック方向に飛ばすためのオフセット値。
//   .zero のときは通常表示。非ゼロのとき、easeIn アニメーションで
//   フリック方向に移動しながら画面外に消える。
//   LazyVGrid 内では offset はレイアウトに影響しないため、
//   タイルが飛び去っても空白スロットが一瞬残るが、
//   直後の throwToBottom によるグリッド再配置で自然に埋まる。

struct GamePickerTile: View {

    let game:      GamePickerSelection
    /// フリック方向への飛び出しオフセット（.zero = 通常表示）
    let flyOffset: CGSize
    let onTap:     () -> Void
    let onFlick:   (_ translation: CGSize, _ velocity: CGSize) -> Void

    private let tapDistanceThreshold: CGFloat = 15

    @State private var isPressed = false

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
        // flyOffset が非ゼロのとき easeIn でフリック方向に飛び出す
        // isPressed のスケールと合成し、flyOffset 中はスケール 1.0 に固定する
        .scaleEffect(isPressed && flyOffset == .zero ? 0.94 : 1.0)
        .offset(flyOffset)
        // flyOffset のアニメーションは TitleView.handleFlick 内の withAnimation で制御する。
        // ここに .animation(value: flyOffset) を書くとリセット時（→ .zero）にも
        // アニメーションが適用されて残像が発生するため、あえて省略している。
        .animation(.easeInOut(duration: 0.1), value: isPressed)
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    if !isPressed { isPressed = true }
                }
                .onEnded { value in
                    isPressed = false
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
