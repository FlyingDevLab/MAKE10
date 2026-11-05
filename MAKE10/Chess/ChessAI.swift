//
//  ChessAI.swift
//  FDL-TenBlitz
//
//  先を読む相手（「あそぶ」のコンピュータ）。Web 版 chess-ai.js の移植に、8〜10 段を足したもの。
//
// ★ 何を良しとするか（Web 版と同じ）★
//   駒のねうち（これが大半）＋ マスの良し悪し ＋ 少しの気まぐれ。
//   下の段はこれだけで指す。なぜその手なのかを、人が読んで追える範囲に留めている。
//   中ほどの段から上は、もっと細かく見る（下の 4）。
//
// ★ Web 版から変えたところ ★
//   1. マスの良し悪しの向きを直した。
//      Web 版は白の表を上下ひっくり返して引いているが、表は白から見た形（上が 8 段目）で
//      書いてあるので、白はそのまま、黒をひっくり返すのが正しい。Web 版のままだと
//      ポーンを進めるほど点が下がり（e2-e4 で −25）、キングは敵陣へ向かいたがる。
//   2. 全 10 段にして、全体を強くした。上の段は Web 版では読めない深さを読む。
//   3. 速くした（同じ深さなら、選ぶ手の評価は変わらない）。
//      ・一度調べた局面を覚える（置換表）
//      ・良さそうな手から調べる（置換表の手・取る手・キラー手・履歴）
//      置換表は「残りの深さがちょうど同じ」ときだけ点を使う。
//      深いほうの点まで流用すると、段ごとの読みの深さが崩れるため。
//   4. 中ほどの段から上は、局面をもっと細かく見る（rich）。
//      Web 版の見方だけでは、有利になっても勝ち切れず、千日手の引き分けが多かった。
//      ・終盤のキングは中央へ、ポーンが進むほど強い（パスポーン）
//      ・ビショップ 2 枚・開いた筋のルーク・キングの前のポーン
//      ・駒で勝っている終盤は、相手のキングを隅へ追い詰める
//   5. 上の段は読みの枝を落として深く読み（prunes）、千日手を避ける（avoidsRepetition）。
//
// ★ 深さは固定。端末の速さで強さを変えない ★
//   時間だけで区切ると、速い端末ほど深く読んで強くなる。
//   budget は強さのためではなく、遅い端末を守るための安全弁で、
//   超えたら最後に読み終わった深さの答えを使う。
//
// ★ 確かめたこと ★
//   rich・prunes・avoidsRepetition を使わない読みは、マスの向きを直した chess-ai.js と
//   局面の点数と読みの結果の点数が一致すること（2026-11-05）。
//   段の強さは隣の段との対局で確かめた。検証のスクリプトはこのリポジトリに入れていない。
//
// 裏のスレッドで呼ぶこと。深い段は 1 手に数秒かかることがある。
//

import Foundation

nonisolated enum ChessAI {

    /// 段ごとの設定。
    struct Settings: Sendable {
        /// 読む深さ
        var depth: Int
        /// いちばん良い手から、これだけ落ちる手までは同じとみなす幅。100 はポーン 1 枚ぶん。
        /// 広いほど、読めてはいるのに雑な手を選ぶ
        var slack: Int
        /// 取り合いを何手まで追うか（静止探索の底）。0 なら追わない
        var quiescence: Int
        /// なにも見ないで指す割合
        var blunder: Double = 0
        /// 3 回目の同一局面になる手を引き分けとして数え、読みの中でも同じ局面を避けるか
        var avoidsRepetition = false
        /// 局面を細かく見るか（このファイル冒頭の 4）
        var rich = false
        /// 枝を落として深く読むか。「深さ」は目安になるが、同じ時間でずっと先まで読める
        var prunes = false
    }

    /// 強さのはしご。段のことは画面に出さない（ChessLadder.swift）。
    /// 1〜2 段は「ただで取れる駒を取る」練習の相手なので、ときどき何も見ずに指す。
    static let levels: [Settings] = [
        // 1 段 3 回に 1 回ほど、なにも見ないで指す。ただで駒を置いていく
        Settings(depth: 1, slack: 250, quiescence: 0, blunder: 0.35),
        // 2 段 ときどき、なにも見ないで指す
        Settings(depth: 1, slack: 150, quiescence: 1, blunder: 0.12),
        // 3 段 取り返しが見える
        Settings(depth: 1, slack: 80, quiescence: 2),
        // 4 段 相手の返しが見える
        Settings(depth: 2, slack: 50, quiescence: 4, rich: true),
        // 5 段
        Settings(depth: 3, slack: 25, quiescence: 4, rich: true),
        // 6 段 2 手の組み合わせが見える
        Settings(depth: 4, slack: 10, quiescence: 4, rich: true),
        // 7 段〜 Web 版では読めない深さ
        Settings(depth: 5, slack: 0, quiescence: 4, avoidsRepetition: true, rich: true, prunes: true),
        Settings(depth: 6, slack: 0, quiescence: 6, avoidsRepetition: true, rich: true, prunes: true),
        Settings(depth: 7, slack: 0, quiescence: 6, avoidsRepetition: true, rich: true, prunes: true),
        Settings(depth: 9, slack: 0, quiescence: 6, avoidsRepetition: true, rich: true, prunes: true),
    ]

    /// 遅い端末を守る安全弁（秒）。
    static let defaultBudget: TimeInterval = 8

    fileprivate static let mate = 100_000
    fileprivate static let infinity = 10_000_000

    // MARK: 局面の点数

    /// 駒のねうち。1 ポーン＝100 で数える。マスの良し悪しを足すので細かい目盛りを使う。
    fileprivate static let values: [Int32] = [100, 320, 330, 500, 900, 20_000]

    /// マスの良し悪し。白から見た値で、盤の並び（上が 8 段目、0 = a8）のまま書く。
    /// 「中央に効く駒は良い」「ポーンは進むほど良い」「ナイトは隅がいちばん悪い」という
    /// よく知られた目安をなぞったもの。
    private static let squareValues: [[Int32]] = [
        // ポーン
        [ 0,  0,  0,  0,  0,  0,  0,  0,
         50, 50, 50, 50, 50, 50, 50, 50,
         10, 10, 20, 30, 30, 20, 10, 10,
          5,  5, 10, 25, 25, 10,  5,  5,
          0,  0,  0, 20, 20,  0,  0,  0,
          5, -5,-10,  0,  0,-10, -5,  5,
          5, 10, 10,-20,-20, 10, 10,  5,
          0,  0,  0,  0,  0,  0,  0,  0],
        // ナイト
        [-50,-40,-30,-30,-30,-30,-40,-50,
         -40,-20,  0,  0,  0,  0,-20,-40,
         -30,  0, 10, 15, 15, 10,  0,-30,
         -30,  5, 15, 20, 20, 15,  5,-30,
         -30,  0, 15, 20, 20, 15,  0,-30,
         -30,  5, 10, 15, 15, 10,  5,-30,
         -40,-20,  0,  5,  5,  0,-20,-40,
         -50,-40,-30,-30,-30,-30,-40,-50],
        // ビショップ
        [-20,-10,-10,-10,-10,-10,-10,-20,
         -10,  0,  0,  0,  0,  0,  0,-10,
         -10,  0,  5, 10, 10,  5,  0,-10,
         -10,  5,  5, 10, 10,  5,  5,-10,
         -10,  0, 10, 10, 10, 10,  0,-10,
         -10, 10, 10, 10, 10, 10, 10,-10,
         -10,  5,  0,  0,  0,  0,  5,-10,
         -20,-10,-10,-10,-10,-10,-10,-20],
        // ルーク
        [  0,  0,  0,  0,  0,  0,  0,  0,
           5, 10, 10, 10, 10, 10, 10,  5,
          -5,  0,  0,  0,  0,  0,  0, -5,
          -5,  0,  0,  0,  0,  0,  0, -5,
          -5,  0,  0,  0,  0,  0,  0, -5,
          -5,  0,  0,  0,  0,  0,  0, -5,
          -5,  0,  0,  0,  0,  0,  0, -5,
           0,  0,  0,  5,  5,  0,  0,  0],
        // クイーン
        [-20,-10,-10, -5, -5,-10,-10,-20,
         -10,  0,  0,  0,  0,  0,  0,-10,
         -10,  0,  5,  5,  5,  5,  0,-10,
          -5,  0,  5,  5,  5,  5,  0, -5,
           0,  0,  5,  5,  5,  5,  0, -5,
         -10,  5,  5,  5,  5,  5,  0,-10,
         -10,  0,  5,  0,  0,  0,  0,-10,
         -20,-10,-10, -5, -5,-10,-10,-20],
        // キング。駒が多いうちは隅に隠れている方が良い。
        // 終盤は逆に中央へ出た方が良いが、そこは見ていない
        [-30,-40,-40,-50,-50,-40,-40,-30,
         -30,-40,-40,-50,-50,-40,-40,-30,
         -30,-40,-40,-50,-50,-40,-40,-30,
         -30,-40,-40,-50,-50,-40,-40,-30,
         -20,-30,-30,-40,-40,-30,-30,-20,
         -10,-20,-20,-20,-20,-20,-20,-10,
          20, 20,  0,  0,  0,  0, 20, 20,
          20, 30, 10,  0,  0, 10, 30, 20],
    ]

    /// 駒のねうち ＋ マスの良し悪し。[種類 × 2 + 色] × 64 + マス
    fileprivate nonisolated(unsafe) static let scoreTable: UnsafePointer<Int32> = {
        let table = UnsafeMutablePointer<Int32>.allocate(capacity: 12 * 64)
        for type in 0..<6 {
            for square in 0..<64 {
                table[(type * 2) * 64 + square] = values[type] + squareValues[type][square]
                // 黒は上下をひっくり返す
                table[(type * 2 + 1) * 64 + square] = values[type] + squareValues[type][square ^ 56]
            }
        }
        return UnsafePointer(table)
    }()

    /// 局面の点数。color から見た点で、color が良ければ正。
    static func evaluate(_ position: ChessPosition, for color: ChessColor) -> Int {
        let table = scoreTable
        var score: Int32 = 0
        for type in 0..<6 {
            let bitboard = position.bitboard(of: ChessPieceType(rawValue: UInt8(type)) ?? .pawn)
            var white = bitboard & position.whites
            while white != 0 {
                score &+= table[(type &* 2) &* 64 &+ white.trailingZeroBitCount]
                white &= white &- 1
            }
            var black = bitboard & position.blacks
            while black != 0 {
                score &-= table[(type &* 2 &+ 1) &* 64 &+ black.trailingZeroBitCount]
                black &= black &- 1
            }
        }
        return color == .white ? Int(score) : -Int(score)
    }

    /// 終盤のキングのマスの良し悪し。中央へ出た方が良い。
    private static let kingEndgame: [Int32] = [
        -50,-40,-30,-20,-20,-30,-40,-50,
        -30,-20,-10,  0,  0,-10,-20,-30,
        -30,-10, 20, 30, 30, 20,-10,-30,
        -30,-10, 30, 40, 40, 30,-10,-30,
        -30,-10, 30, 40, 40, 30,-10,-30,
        -30,-10, 20, 30, 30, 20,-10,-30,
        -30,-30,  0,  0,  0,  0,-30,-30,
        -50,-30,-30,-30,-30,-30,-30,-50,
    ]

    /// [色 × 64 + マス]。終盤のキングの点から、ふつうのキングの点を引いたもの
    fileprivate nonisolated(unsafe) static let kingShift: UnsafePointer<Int32> = {
        let table = UnsafeMutablePointer<Int32>.allocate(capacity: 128)
        for square in 0..<64 {
            table[square] = kingEndgame[square] - squareValues[5][square]
            table[64 + square] = kingEndgame[square ^ 56] - squareValues[5][square ^ 56]
        }
        return UnsafePointer(table)
    }()

    /// [色 × 64 + マス]。そのポーンより前の、同じ筋と隣の筋。相手のポーンがいなければパスポーン
    fileprivate nonisolated(unsafe) static let passedMask: UnsafePointer<UInt64> = {
        let table = UnsafeMutablePointer<UInt64>.allocate(capacity: 128)
        table.initialize(repeating: 0, count: 128)
        for square in 0..<64 {
            let file = ChessSquare.file(square), rank = ChessSquare.rank(square)
            for f in max(0, file - 1)...min(7, file + 1) {
                for r in 1...8 {
                    let target = UInt64(1) << UInt64(ChessSquare.at(file: f, rank: r))
                    if r > rank { table[square] |= target }
                    if r < rank { table[64 + square] |= target }
                }
            }
        }
        return UnsafePointer(table)
    }()

    /// パスポーンのねうち。段（手前から 0〜7）ごと
    private static let passedBonus: [Int] = [0, 5, 10, 20, 40, 70, 120, 0]

    /// 局面の点数（細かく見る版）。color から見た点。
    static func evaluateRich(_ position: ChessPosition, for color: ChessColor) -> Int {
        var score = evaluate(position, for: .white)
        let whites = position.whites, blacks = position.blacks
        let pawns = position.pawns

        // どれだけ終盤か。駒が減るほど phase が小さい（24 が開始の局面）
        let phase = min(24, (position.knights | position.bishops).nonzeroBitCount
                            + position.rooks.nonzeroBitCount * 2 + position.queens.nonzeroBitCount * 4)
        let endgame = 24 - phase

        // キング
        let shift = kingShift
        let whiteKing = position.kings & whites, blackKing = position.kings & blacks
        let whiteKingSquare = whiteKing.trailingZeroBitCount, blackKingSquare = blackKing.trailingZeroBitCount
        if whiteKing != 0 { score += Int(shift[whiteKingSquare]) * endgame / 24 }
        if blackKing != 0 { score -= Int(shift[64 &+ blackKingSquare]) * endgame / 24 }

        // キングの前のポーン。駒が多いうちだけ見る
        if phase >= 10 {
            let t = ChessTables.shared
            if whiteKing != 0 {
                let front = t.pawn[whiteKingSquare] | (whiteKing >> 8)
                score += (front & pawns & whites).nonzeroBitCount * 12 * phase / 24
            }
            if blackKing != 0 {
                let front = t.pawn[64 &+ blackKingSquare] | (blackKing << 8)
                score -= (front & pawns & blacks).nonzeroBitCount * 12 * phase / 24
            }
        }

        // パスポーン。終盤ほど重い
        let mask = passedMask
        var bits = pawns & whites
        while bits != 0 {
            let s = bits.trailingZeroBitCount
            bits &= bits &- 1
            if mask[s] & pawns & blacks == 0 {
                score += passedBonus[8 &- (s >> 3) &- 1] * (24 + endgame) / 24
            }
        }
        bits = pawns & blacks
        while bits != 0 {
            let s = bits.trailingZeroBitCount
            bits &= bits &- 1
            if mask[64 &+ s] & pawns & whites == 0 {
                score -= passedBonus[s >> 3] * (24 + endgame) / 24
            }
        }

        // ビショップ 2 枚
        if (position.bishops & whites).nonzeroBitCount >= 2 { score += 30 }
        if (position.bishops & blacks).nonzeroBitCount >= 2 { score -= 30 }

        // 開いた筋のルーク
        let fileA: UInt64 = 0x0101_0101_0101_0101
        bits = position.rooks
        while bits != 0 {
            let s = bits.trailingZeroBitCount
            bits &= bits &- 1
            let file = fileA << UInt64(s & 7)
            let white = whites >> UInt64(s) & 1 != 0
            if file & pawns == 0 {
                score += white ? 20 : -20
            } else if file & pawns & (white ? whites : blacks) == 0 {
                score += white ? 10 : -10
            }
        }

        // 勝っている終盤は、相手のキングを隅へ追い詰め、自分のキングを近づける
        if phase <= 8 && abs(score) >= 300 && whiteKing != 0 && blackKing != 0 {
            let loser = score > 0 ? blackKingSquare : whiteKingSquare
            let winner = score > 0 ? whiteKingSquare : blackKingSquare
            let file = loser & 7, rank = loser >> 3
            let edge = max(3 &- file, file &- 4) &+ max(3 &- rank, rank &- 4)
            let distance = abs(file &- (winner & 7)) &+ abs(rank &- (winner >> 3))
            let mopUp = edge &* 12 &+ (14 &- distance) &* 5
            score += score > 0 ? mopUp : -mopUp
        }
        return color == .white ? score : -score
    }

    // MARK: 手を選ぶ

    struct Choice: Sendable {
        let move: ChessMove
        /// 読み終えた深さ。何も見ずに指した手と、指せる手が 1 つのときは 0
        let depth: Int
        /// その手の点数
        let score: Int
        /// 調べた局面の数
        let nodes: Int
    }

    /// 段を指定して手を選ぶ。合法手が無ければ nil。
    static func choose(in game: ChessGame, level: Int,
                       budget: TimeInterval = defaultBudget,
                       rng: () -> Double = { Double.random(in: 0..<1) },
                       shouldStop: (() -> Bool)? = nil) -> Choice? {
        let index = min(levels.count, max(1, level)) - 1
        return choose(in: game, settings: levels[index], budget: budget, rng: rng, shouldStop: shouldStop)
    }

    /// 設定を直に渡して手を選ぶ。合法手が無ければ nil。
    static func choose(in game: ChessGame, settings: Settings,
                       budget: TimeInterval = defaultBudget,
                       rng: () -> Double = { Double.random(in: 0..<1) },
                       shouldStop: (() -> Bool)? = nil) -> Choice? {
        let position = game.position
        var root = position.legalMoves()
        guard !root.isEmpty else { return nil }
        if root.count == 1 { return Choice(move: root[0], depth: 0, score: 0, nodes: 0) }

        func pick(_ list: [ChessMove]) -> ChessMove {
            list[min(Int(rng() * Double(list.count)), list.count - 1)]
        }

        // なにも見ないで指す回。読む前に決めるので時間も使わない
        if settings.blunder > 0 && rng() < settings.blunder {
            return Choice(move: pick(root), depth: 0, score: 0, nodes: 0)
        }

        let searcher = ChessSearcher(settings: settings, budget: budget, shouldStop: shouldStop,
                                     gameHashes: settings.avoidsRepetition ? game.hashes : [])
        var bestMove = root[0]
        var bestScore = 0
        var reached = 0

        for depth in 1...max(1, settings.depth) {
            var scored: [(move: ChessMove, score: Int)] = []
            scored.reserveCapacity(root.count)
            // 下限を best より slack だけ低くして持ち越す。手ごとに窓を開け直すと、
            // 最初の分かれ道だけ枝刈りが効かない。僅差で並ぶ手の点はそのまま残る
            var floor = -infinity
            for move in root {
                let next = position.applying(move)
                let score: Int
                if settings.avoidsRepetition && game.seenCount(of: next) >= 2 {
                    score = 0
                } else {
                    score = -searcher.search(next, depth: depth - 1, alpha: -infinity, beta: -floor, ply: 1)
                }
                if searcher.aborted { break }
                scored.append((move, score))
                // 窓を切った手は「これ以下」としか分からない値が返る。
                // その値が同点の線と重なると、読み切っていない手が同点に紛れるので、
                // 1 だけ下げて必ず線の外に落とす
                floor = max(floor, score - settings.slack - 1)
            }
            // 時間切れで読み終わらなかった深さは捨てる。途中までの並びで決めると、
            // まだ読んでいない手が「悪い手」として扱われ、浅く読んだときより弱くなる
            if searcher.aborted { break }

            scored.sort { $0.score > $1.score }
            bestScore = scored[0].score
            // 僅差は同じ価値とみなし、その中から選ぶ（毎局おなじにならない）
            bestMove = pick(scored.filter { $0.score >= bestScore - settings.slack }.map(\.move))
            reached = depth
            root = scored.map(\.move)   // 次の深さは良かった手から読む

            // 詰みが見えたら、それ以上深くしても意味がない
            if bestScore >= mate - 100 { break }
        }

        return Choice(move: bestMove, depth: reached, score: bestScore, nodes: searcher.nodes)
    }
}

// MARK: - 読み

/// 1 手を考えるあいだだけ使う作業場。
private nonisolated final class ChessSearcher {

    /// 置換表の 1 行。
    private struct Entry {
        var key: UInt64 = 0
        var score: Int32 = 0
        var move: UInt16 = 0
        var depth: Int8 = -1
        var bound: UInt8 = 0
    }

    private static let boundExact: UInt8 = 0
    private static let boundLower: UInt8 = 1
    private static let boundUpper: UInt8 = 2
    private static let maxPly = 40
    private static let perPly = ChessPosition.moveBufferCapacity

    private let quiescenceDepth: Int
    private let rich: Bool
    private let prunes: Bool
    private let avoidsRepetition: Bool
    /// 実際の対局に現れた局面の札
    private let played: Set<UInt64>
    /// 読みの途中の局面の札。[ply]
    private let path: UnsafeMutablePointer<UInt64>
    private let moves: UnsafeMutablePointer<ChessMove>
    private let ranks: UnsafeMutablePointer<Int32>
    private let table: UnsafeMutablePointer<Entry>
    private let tableMask: UInt64
    private let killers: UnsafeMutablePointer<UInt16>
    private let history: UnsafeMutablePointer<Int32>
    private let deadline: UInt64
    private let shouldStop: (() -> Bool)?

    private(set) var nodes = 0
    private(set) var aborted = false

    init(settings: ChessAI.Settings, budget: TimeInterval, shouldStop: (() -> Bool)?, gameHashes: [UInt64]) {
        quiescenceDepth = settings.quiescence
        rich = settings.rich
        prunes = settings.prunes
        avoidsRepetition = settings.avoidsRepetition
        played = Set(gameHashes)
        path = .allocate(capacity: Self.maxPly + 1)
        path.initialize(repeating: 0, count: Self.maxPly + 1)
        self.shouldStop = shouldStop
        deadline = DispatchTime.now().uptimeNanoseconds &+ UInt64(max(budget, 0) * 1_000_000_000)

        moves = .allocate(capacity: Self.maxPly * Self.perPly)
        ranks = .allocate(capacity: Self.maxPly * Self.perPly)
        // 深く読む段だけ大きな表を使う。1 行 16 バイトなので 16MB
        let size = settings.depth >= 4 ? 1 << 20 : 1 << 12
        table = .allocate(capacity: size)
        table.initialize(repeating: Entry(), count: size)
        tableMask = UInt64(size - 1)
        killers = .allocate(capacity: Self.maxPly * 2)
        killers.initialize(repeating: 0, count: Self.maxPly * 2)
        history = .allocate(capacity: 64 * 64)
        history.initialize(repeating: 0, count: 64 * 64)
    }

    deinit {
        moves.deallocate()
        ranks.deallocate()
        table.deallocate()
        killers.deallocate()
        history.deallocate()
        path.deallocate()
    }

    private func checkTime() {
        if DispatchTime.now().uptimeNanoseconds > deadline || shouldStop?() == true {
            aborted = true
        }
    }

    /// 本体。手番の側から見た点を返す。
    func search(_ position: ChessPosition, depth: Int, alpha alphaIn: Int, beta: Int, ply: Int) -> Int {
        nodes &+= 1
        if nodes & 1023 == 0 { checkTime() }
        if aborted { return 0 }

        // 同じ局面に戻る手は引き分けとして数える。戻れるのは取りもポーンの動きもない間だけ
        if avoidsRepetition {
            path[ply] = position.hash
            if position.halfMove > 0 {
                if played.contains(position.hash) { return 0 }
                var back = ply &- 2
                while back >= 1 {
                    if path[back] == position.hash { return 0 }
                    back &-= 2
                }
            }
        }

        let color = position.turn
        let base = moves + ply &* Self.perPly

        if depth <= 0 {
            // 深さを使い切っても、詰みとステイルメイトだけは見る
            let count = position.pseudoMoves(for: color, into: base)
            var hasMove = false
            for i in 0..<count where !position.leavesKingAttacked(base[i], color) {
                hasMove = true
                break
            }
            if !hasMove { return position.inCheck(color) ? -ChessAI.mate : 0 }
            return quiesce(position, alpha: alphaIn, beta: beta, left: quiescenceDepth, ply: ply)
        }

        var alpha = alphaIn
        var tableMove: UInt16 = 0
        let slot = table + Int(truncatingIfNeeded: position.hash & tableMask)
        if slot.pointee.key == position.hash {
            tableMove = slot.pointee.move
            // 枝を落とす段は、より深く読んだ点も使う。ほかの段は読みの深さを崩さない
            if Int(slot.pointee.depth) == depth || (prunes && Int(slot.pointee.depth) > depth) {
                let score = Int(slot.pointee.score)
                switch slot.pointee.bound {
                case Self.boundExact: return score
                case Self.boundLower: if score >= beta { return score }
                default:              if score <= alpha { return score }
                }
            }
        }

        let inCheck = prunes && position.inCheck(color)

        // 自分がパスしても相手を上回るなら、この枝は読むまでもない
        if prunes && !inCheck && depth >= 3 && ply &+ 6 < Self.maxPly && beta < ChessAI.mate - 100
            && position.pieces(of: color) & ~(position.pawns | position.kings) != 0 {
            let score = -search(position.passingTurn(), depth: depth &- 3, alpha: -beta, beta: -beta &+ 1, ply: ply &+ 1)
            if aborted { return 0 }
            if score >= beta { return beta }
        }

        let count = position.pseudoMoves(for: color, into: base)
        let rank = ranks + ply &* Self.perPly
        rankMoves(base, rank, count, tableMove: tableMove, ply: ply)

        var best = -ChessAI.infinity
        var bestMove: UInt16 = 0
        var legal = 0
        for i in 0..<count {
            // まだ調べていない中で、いちばん良さそうな手を前へ出す
            var top = i
            for k in (i &+ 1)..<max(count, i &+ 1) where rank[k] > rank[top] { top = k }
            if top != i {
                swap(&base[i], &base[top])
                swap(&rank[i], &rank[top])
            }

            let move = base[i]
            var next = position
            next.apply(move)
            if next.inCheck(color) { continue }
            legal &+= 1

            var score: Int
            let givesCheck = prunes && next.inCheck(next.turn)
            // チェックの応手は 1 手ぶん余計に読む
            let extended = inCheck && ply &+ 6 < Self.maxPly ? depth : depth &- 1
            // 後ろの手（有望でない静かな手）は浅く読み、良さそうなら読み直す
            if prunes && legal > 3 && depth >= 3 && !inCheck && !givesCheck && !move.isCapture
                && move.promotion == nil {
                let reduction = legal > 10 && depth >= 5 ? 2 : 1
                score = -search(next, depth: extended &- reduction, alpha: -alpha &- 1, beta: -alpha, ply: ply &+ 1)
                if aborted { return 0 }
                if score > alpha {
                    score = -search(next, depth: extended, alpha: -beta, beta: -alpha, ply: ply &+ 1)
                }
            } else {
                score = -search(next, depth: extended, alpha: -beta, beta: -alpha, ply: ply &+ 1)
            }
            if aborted { return 0 }
            if score > best {
                best = score
                bestMove = move.packed
            }
            if best > alpha { alpha = best }
            if alpha >= beta {
                if !move.isCapture {
                    let packed = move.packed
                    if killers[ply &* 2] != packed {
                        killers[ply &* 2 &+ 1] = killers[ply &* 2]
                        killers[ply &* 2] = packed
                    }
                    history[move.from &* 64 &+ move.to] &+= Int32(truncatingIfNeeded: depth &* depth)
                }
                break
            }
        }

        if legal == 0 {
            // 近い詰みほど良い点にする。depth は「あと何手読むか」の残りで、
            // 根に近いほど大きい。だから depth を足す。引くと遠い詰みのほうが良い点になる
            return position.inCheck(color) ? -(ChessAI.mate + depth) : 0
        }

        let bound = best <= alphaIn ? Self.boundUpper : (best >= beta ? Self.boundLower : Self.boundExact)
        slot.pointee = Entry(key: position.hash, score: Int32(truncatingIfNeeded: best), move: bestMove,
                             depth: Int8(truncatingIfNeeded: depth), bound: bound)
        return best
    }

    /// 手に「調べる順番の点」を付ける。
    @inline(__always)
    private func rankMoves(_ list: UnsafeMutablePointer<ChessMove>, _ rank: UnsafeMutablePointer<Int32>,
                           _ count: Int, tableMove: UInt16, ply: Int) {
        let first = killers[ply &* 2], second = killers[ply &* 2 &+ 1]
        for i in 0..<count {
            let move = list[i]
            let packed = move.packed
            if packed == tableMove {
                rank[i] = 1 << 30
            } else if move.capturedCode != ChessMove.none {
                let victim = ChessAI.values[Int(move.capturedCode & 7)]
                let attacker = ChessAI.values[Int(move.pieceCode & 7)]
                rank[i] = (1 << 24) &+ victim &* 10 &- attacker / 10
            } else if packed == first {
                rank[i] = 1 << 23
            } else if packed == second {
                rank[i] = 1 << 22
            } else {
                rank[i] = min(history[move.from &* 64 &+ move.to], (1 << 22) - 1)
            }
        }
    }

    /// 取る手だけを、読み切るまで続ける（静止探索）。
    /// 深さで打ち切ると「最後の 1 手でクイーンを取った」ところで数え終わり、
    /// 次に取り返されるのが見えない。
    private func quiesce(_ position: ChessPosition, alpha alphaIn: Int, beta: Int, left: Int, ply: Int) -> Int {
        nodes &+= 1
        if nodes & 1023 == 0 { checkTime() }
        if aborted { return 0 }

        let color = position.turn
        let stand = rich ? ChessAI.evaluateRich(position, for: color) : ChessAI.evaluate(position, for: color)
        if left <= 0 { return stand }
        if stand >= beta { return beta }
        var alpha = max(alphaIn, stand)

        let base = moves + ply &* Self.perPly
        let rank = ranks + ply &* Self.perPly
        let count = position.pseudoMoves(for: color, capturesOnly: true, into: base)
        for i in 0..<count {
            rank[i] = ChessAI.values[Int(base[i].capturedCode & 7)]
        }

        for i in 0..<count {
            var top = i
            for k in (i &+ 1)..<max(count, i &+ 1) where rank[k] > rank[top] { top = k }
            if top != i {
                swap(&base[i], &base[top])
                swap(&rank[i], &rank[top])
            }

            let move = base[i]
            // 明らかに損な取り方は読まない。
            // 自分より高い駒を取るなら、取り返されても損にならないので計算を省く
            let attackerValue = ChessAI.values[Int(move.pieceCode & 7)]
            if ChessAI.values[Int(move.capturedCode & 7)] < attackerValue && position.exchange(of: move) < 0 {
                continue
            }
            var next = position
            next.apply(move)
            if next.inCheck(color) { continue }

            let score = -quiesce(next, alpha: -beta, beta: -alpha, left: left &- 1, ply: ply &+ 1)
            if aborted { return 0 }
            if score >= beta { return beta }
            if score > alpha { alpha = score }
        }
        return alpha
    }
}
