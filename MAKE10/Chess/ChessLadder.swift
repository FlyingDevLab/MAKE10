//
//  ChessLadder.swift
//  FDL-TenBlitz
//
//  コンピュータの強さ（段）の上げ下げ。対局の結果で自動で動き、画面には何も出さない。
//  段が目的になると、勝った嬉しさが「段が上がった」にすり替わるため。
//
// ★ 上げ下げの決まり ★
//   勝ち                     +1
//   チェックメイトされた     半分（端数は切り上げ。10 → 5、3 → 2）
//   投了                     −2（ただしチェックメイトより重くしない）
//   引き分け                 −2
//   もどす                   押すたびに −2
//
//   不意に詰まされるより、負けを読んで潔く投げる方を軽くしてある。
//   コンピュータ戦に「はじめから」は無いので、負けそうな局を消して段を守ることはできない。
//   途中保存があるので、アプリを閉じても逃げられない。
//
// ★ 段が動く対局 ★
//   「コンピュータと さす」の通常の対局だけ。「ならべて」のコンピュータ戦では動かさない。
//   詰む直前の形を並べて勝てば、いくらでも段を上げられてしまうため。
//

import Foundation

nonisolated enum ChessLadder {
    static let minLevel = 1
    static let maxLevel = 10
    /// はじめは 1 段（いちばんやさしい）。入門の相手が最初に見せるものが負けでは話が逆
    static let startLevel = 1

    enum Result: Sendable {
        case win
        case draw
        case checkmated
        case resigned
    }

    private static func clamp(_ level: Int) -> Int {
        min(maxLevel, max(minLevel, level))
    }

    private static func halvedRoundingUp(_ level: Int) -> Int {
        (level + 1) / 2
    }

    /// 決着のあとの段。
    static func level(after result: Result, from level: Int) -> Int {
        switch result {
        case .win:
            return clamp(level + 1)
        case .draw:
            return clamp(level - 2)
        case .checkmated:
            return clamp(halvedRoundingUp(level))
        case .resigned:
            // 3 段では −2 の 1 段より、詰みの 2 段のほうが軽い。投了を詰みより重くしない
            return clamp(max(level - 2, halvedRoundingUp(level)))
        }
    }

    /// 「もどす」を 1 回押したあとの段。押した直後から相手が弱くなる。
    static func levelAfterUndo(from level: Int) -> Int {
        clamp(level - 2)
    }
}
