//
//  ChessCPU.swift
//  FDL-TenBlitz
//
//  第 1 巻のおまけ「コンピュータと さす」の黒。Web 版 chess-cpu.js の移植。
//
//  先を読まない。局面の良し悪しを点数にもしない。上から順に
//  「当てはまったら、それを指す」だけの決まりごと。白をこちらから攻めに来ないので、
//  駒の動きを覚える練習台になる。強くすると教材として壊れる（「あそぶ」の相手は ChessAI）。
//
//    1. 取り返す  白が直前に取ったマスに、黒の利きがあれば取り返す。損得は見ない
//    2. ただ取り  白の駒で、守られていないものを取れるなら取る。ねうちの大きいほう
//    3. 守る      取られそうな黒の駒があれば、逃がすか、守りを足す
//    4. それ以外  黒の陣地（5〜8 段）に留まる。白に狙われているマスへは入らない
//
//  規則の中で候補が複数あれば、乱数で 1 つ選ぶ。毎局おなじ展開にならない。
//

import Foundation

nonisolated enum ChessCPU {

    /// 黒の陣地。5 段目から 8 段目
    private static let homeMinRank = 5

    /// 黒の駒のうち、白に狙われていて、黒が守っていないもののねうちの合計。
    /// キングは数えない（キングへの攻撃はチェックで、合法手が既に解決している）。
    private static func hangingValue(_ position: ChessPosition) -> Int {
        var sum = 0
        var bits = position.blacks & ~position.kings
        while bits != 0 {
            let s = bits.trailingZeroBitCount
            bits &= bits &- 1
            if position.isAttacked(s, by: .white), !position.isAttacked(s, by: .black),
               let piece = position.piece(at: s) {
                sum += piece.type.value
            }
        }
        return sum
    }

    /// 規則に当てはまった手の候補と、当てはまった規則の名前。合法手が無ければ nil。
    /// - Parameter lastMove: 白が直前に指した手
    static func candidates(_ position: ChessPosition, lastMove: ChessMove?) -> (moves: [ChessMove], rule: String)? {
        let legal = position.legalMoves(for: .black)
        guard !legal.isEmpty else { return nil }

        // 1. 取り返す
        if let last = lastMove, last.isCapture {
            let back = legal.filter { $0.isCapture && $0.capturedAt == last.to }
            if !back.isEmpty { return (back, "1") }
        }

        // 2. ただ取り
        var best = 0
        var free: [ChessMove] = []
        for move in legal {
            guard let captured = move.captured else { continue }
            // 取ったあと、その駒が白に取り返されるなら「守られていた」
            if position.applying(move).isAttacked(move.to, by: .white) { continue }
            let value = captured.type.value
            if value > best {
                best = value
                free = [move]
            } else if value == best {
                free.append(move)
            }
        }
        if !free.isEmpty { return (free, "2") }

        // 3. 守る。手を指した後に取られそうな駒が減る手だけを選ぶ
        let before = hangingValue(position)
        if before > 0 {
            var low = before
            var saves: [ChessMove] = []
            for move in legal {
                let after = hangingValue(position.applying(move))
                if after >= before { continue }
                if after < low {
                    low = after
                    saves = [move]
                } else if after == low {
                    saves.append(move)
                }
            }
            if !saves.isEmpty { return (saves, "3") }
        }

        // 4. それ以外。安全なマスだけ、できれば陣地の中だけ。
        // 当てはまらなければ順に落とす。合法手が 1 つでもあれば必ず指す
        var safe: [ChessMove] = []
        var home: [ChessMove] = []
        for move in legal where !position.applying(move).isAttacked(move.to, by: .white) {
            safe.append(move)
            if ChessSquare.rank(move.to) >= homeMinRank { home.append(move) }
        }
        if !home.isEmpty { return (home, "4") }
        if !safe.isEmpty { return (safe, "4b") }
        return (legal, "4c")
    }

    /// 黒の手を選ぶ。
    static func choose(_ position: ChessPosition, lastMove: ChessMove?,
                       rng: () -> Double = { Double.random(in: 0..<1) }) -> ChessMove? {
        guard let found = candidates(position, lastMove: lastMove) else { return nil }
        let index = min(Int(rng() * Double(found.moves.count)), found.moves.count - 1)
        return found.moves[index]
    }
}
