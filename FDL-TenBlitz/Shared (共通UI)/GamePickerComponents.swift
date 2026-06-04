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

import SwiftUI

// MARK: - GamePickerSelection

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

struct GamePickerTile: View {

    let game:      GamePickerSelection
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
        .scaleEffect(isPressed && flyOffset == .zero ? 0.94 : 1.0)
        .offset(flyOffset)
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
