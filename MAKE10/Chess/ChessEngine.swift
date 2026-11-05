//
//  ChessEngine.swift
//  FDL-TenBlitz
//
//  チェスのルール判定。局面を持ち、合法手を数え、決着を判定し、棋譜（SAN）を書き読みする。
//  画面のことは何も知らない。Web 版 /kids/chess/shared/chess.js の移植で、
//  答えが同じになることを機械で突き合わせてある（下の「確かめたこと」）。
//
// ★ Web 版から変えたところ ★
//   Web 版は盤を 64 個の文字の配列で持ち、手を指すたびに配列を複製する。
//   読みやすいが、1手を深く読むには遅い（深さ 6 で 6〜34 秒、Mac の実測）。
//   アプリでは 10 段目に深さ 6 を読ませたいので、盤を「ビットボード」で持つ。
//
//     pawns … kings   その種類の駒がいるマスに 1 が立った 64 ビットの整数
//     whites / blacks その色の駒がいるマス
//
//   ビットの番号はマスの番号と同じ（0 が a8、63 が h1）。Web 版のマス番号が
//   そのまま使えるので、レッスンの表（FEN・マスの名前）を変えずに済む。
//
// ★ 手を指すと新しい局面ができる（Web 版と同じ）★
//   ChessPosition は数十バイトの値型で、手を指すときはコピーして書き換える。
//   「指して戻す」方式にしない理由は Web 版と同じで、キャスリングの権利や
//   アンパッサンの復元を 1 つ忘れた瞬間に、盤は正しいのにルールだけが狂うため。
//   ヒープを使わないので、コピーは読みの速さにほとんど響かない。
//
// ★ 合法手の作り方（Web 版と同じ）★
//   ルール違反を含む手を全部作り、指してみて自分のキングが取られる形を落とす。
//   ピンを事前に見る方式より遅いが、間違えようがない。
//
// ★ 確かめたこと（2026-11-05）★
//   1. perft: chess.js の冒頭に書いてある既知の値すべてと一致
//   2. chess.js との突き合わせ: 乱数で指した対局の全局面で、合法手・棋譜・FEN・
//      決着の種類・取り合いの損得が同じ答えになること
//   検証のスクリプトはこのリポジトリに入れていない（公開するのは遊ぶコードだけ）。
//   ルールに手を入れたら、同じ確認をやり直すこと。
//
// ★ nonisolated の理由 ★
//   このプロジェクトは既定で MainActor だが、ここは裏のスレッドで読むので外している。
//

import Foundation

// MARK: - 色と駒

nonisolated enum ChessColor: UInt8, Hashable, Sendable {
    case white = 0
    case black = 1

    var opposite: ChessColor { self == .white ? .black : .white }
}

nonisolated enum ChessPieceType: UInt8, Hashable, Sendable, CaseIterable {
    case pawn = 0, knight, bishop, rook, queen, king

    /// 棋譜と FEN の 1 文字（白＝大文字）
    var letter: Character {
        switch self {
        case .pawn:   return "P"
        case .knight: return "N"
        case .bishop: return "B"
        case .rook:   return "R"
        case .queen:  return "Q"
        case .king:   return "K"
        }
    }

    /// 駒のねうち。ポーン1・ナイト3・ビショップ3・ルーク5・クイーン9。
    /// キングは取り合いの判定にだけ使うので大きな数を置く（chess.js の VALUE と同じ）。
    var value: Int {
        switch self {
        case .pawn:   return 1
        case .knight: return 3
        case .bishop: return 3
        case .rook:   return 5
        case .queen:  return 9
        case .king:   return 1000
        }
    }

    init?(letter: Character) {
        switch letter {
        case "P": self = .pawn
        case "N": self = .knight
        case "B": self = .bishop
        case "R": self = .rook
        case "Q": self = .queen
        case "K": self = .king
        default:  return nil
        }
    }
}

nonisolated struct ChessPiece: Hashable, Sendable {
    let type: ChessPieceType
    let color: ChessColor

    init(_ type: ChessPieceType, _ color: ChessColor) {
        self.type = type
        self.color = color
    }

    /// FEN の 1 文字から。白は大文字、黒は小文字。
    init?(fen: Character) {
        let upper = Character(String(fen).uppercased())
        guard let type = ChessPieceType(letter: upper) else { return nil }
        self.type = type
        self.color = fen == upper ? .white : .black
    }

    var fen: Character {
        color == .white ? type.letter : Character(String(type.letter).lowercased())
    }

    /// 手の中に詰めて持つときの番号。種類 ＋ 色 × 8。
    fileprivate var code: UInt8 { type.rawValue | (color.rawValue << 3) }

    fileprivate init(code: UInt8) {
        type = ChessPieceType(rawValue: code & 7) ?? .pawn
        color = code & 8 == 0 ? .white : .black
    }
}

// MARK: - マス

/// マスは 0〜63 の番号で持つ。0 が a8、63 が h1（FEN の書き始めから順）。
nonisolated enum ChessSquare {
    private static let files = Array("abcdefgh")

    /// 筋。0 = a 列
    static func file(_ i: Int) -> Int { i & 7 }
    /// 段。1 = 1 段目
    static func rank(_ i: Int) -> Int { 8 - (i >> 3) }
    /// 'e4' の形の名前
    static func name(_ i: Int) -> String { "\(files[file(i)])\(rank(i))" }

    /// 筋と段から番号へ。盤の外なら -1
    static func at(file: Int, rank: Int) -> Int {
        guard (0...7).contains(file), (1...8).contains(rank) else { return -1 }
        return (8 - rank) * 8 + file
    }

    /// 'e4' から番号へ。読めなければ -1
    static func index(_ name: String) -> Int {
        let chars = Array(name.lowercased())
        guard chars.count == 2,
              let file = files.firstIndex(of: chars[0]),
              let rank = chars[1].wholeNumberValue else { return -1 }
        return at(file: file, rank: rank)
    }

    /// マスの色。a1 は黒マス。筋（a=0）と段（1〜8）を足して偶数なら白マス。
    static func isLight(_ i: Int) -> Bool { (file(i) + rank(i)) % 2 == 0 }
}

// MARK: - 手

/// 手。読みの途中で何百万回も作るので、小さな数に詰めて持つ。
///
/// captured と capturedAt を to と別に持っているのはアンパッサンのためだけ。
/// あの手だけ「取った駒が行き先にいない」ので、to から割り出すと必ず間違える。
nonisolated struct ChessMove: Hashable, Sendable {
    enum Castle: Hashable, Sendable { case kingSide, queenSide }

    static let none: UInt8 = 0xFF
    fileprivate static let flagCastleK: UInt8 = 1
    fileprivate static let flagCastleQ: UInt8 = 2
    fileprivate static let flagDouble: UInt8 = 4

    fileprivate let fromSquare: UInt8
    fileprivate let toSquare: UInt8
    /// 動かす駒の番号（種類 ＋ 色 × 8）。読みの途中で表を引くのに使う
    let pieceCode: UInt8
    /// 取る駒の番号。無ければ ChessMove.none
    let capturedCode: UInt8
    fileprivate let capturedSquare: Int8
    fileprivate let promoCode: UInt8
    fileprivate let flags: UInt8

    var from: Int { Int(fromSquare) }
    var to: Int { Int(toSquare) }
    var piece: ChessPiece { ChessPiece(code: pieceCode) }
    var captured: ChessPiece? { capturedCode == Self.none ? nil : ChessPiece(code: capturedCode) }
    /// 取った駒がいたマス。無ければ -1
    var capturedAt: Int { Int(capturedSquare) }
    var promotion: ChessPieceType? {
        promoCode == Self.none ? nil : ChessPieceType(rawValue: promoCode)
    }
    var castle: Castle? {
        if flags & Self.flagCastleK != 0 { return .kingSide }
        if flags & Self.flagCastleQ != 0 { return .queenSide }
        return nil
    }
    var isDoublePush: Bool { flags & Self.flagDouble != 0 }
    var isCapture: Bool { capturedCode != Self.none }

    /// 'e2e4'・'e7e8q' の形。途中保存はこの文字で手を持つ。
    var coordinate: String {
        let tail = promotion.map { String($0.letter).lowercased() } ?? ""
        return ChessSquare.name(from) + ChessSquare.name(to) + tail
    }

    /// 読みの置換表に入れる形。from・to・なる駒が同じなら同じ手とみなせる。
    var packed: UInt16 {
        UInt16(fromSquare) | (UInt16(toSquare) << 6) | (UInt16(promoCode & 7) << 12)
    }
}

// MARK: - 計算済みの表

/// 利きの表と、局面の札（Zobrist ハッシュ）に使う乱数。起動後に 1 度だけ作る。
nonisolated struct ChessTables: @unchecked Sendable {
    let knight: UnsafePointer<UInt64>
    let king: UnsafePointer<UInt64>
    /// そのマスのポーンが取れるマス。[色 × 64 + マス]
    let pawn: UnsafePointer<UInt64>
    /// そのマスから盤の端までの線。[向き × 64 + マス]
    let rays: UnsafePointer<UInt64>
    /// [駒の番号（種類 ＋ 色 × 8）× 64 + マス]
    let zobristPiece: UnsafePointer<UInt64>
    let zobristCastle: UnsafePointer<UInt64>
    let zobristEpFile: UnsafePointer<UInt64>
    let zobristTurn: UInt64

    static let shared = ChessTables()

    // 線の向き。番号が増える向き（S・E・SE・SW）と減る向きで、一番近い駒の探し方が変わる
    static let north = 0, south = 1, east = 2, west = 3
    static let northEast = 4, northWest = 5, southEast = 6, southWest = 7

    private init() {
        func table(_ count: Int) -> UnsafeMutablePointer<UInt64> {
            let p = UnsafeMutablePointer<UInt64>.allocate(capacity: count)
            p.initialize(repeating: 0, count: count)
            return p
        }
        func bit(_ file: Int, _ rank: Int) -> UInt64 {
            let s = ChessSquare.at(file: file, rank: rank)
            return s < 0 ? 0 : UInt64(1) << UInt64(s)
        }

        let knightTable = table(64), kingTable = table(64), pawnTable = table(128), rayTable = table(512)
        let leaps = [(1, 2), (2, 1), (2, -1), (1, -2), (-1, -2), (-2, -1), (-2, 1), (-1, 2)]
        // 順番は上の向きの番号と揃える
        let lines = [(0, 1), (0, -1), (1, 0), (-1, 0), (1, 1), (-1, 1), (1, -1), (-1, -1)]

        for s in 0..<64 {
            let f = ChessSquare.file(s), r = ChessSquare.rank(s)
            for (df, dr) in leaps { knightTable[s] |= bit(f + df, r + dr) }
            for (df, dr) in lines { kingTable[s] |= bit(f + df, r + dr) }
            pawnTable[s]      = bit(f - 1, r + 1) | bit(f + 1, r + 1)   // 白は上へ攻める
            pawnTable[64 + s] = bit(f - 1, r - 1) | bit(f + 1, r - 1)   // 黒は下へ攻める
            for (d, line) in lines.enumerated() {
                var step = 1
                while true {
                    let m = bit(f + line.0 * step, r + line.1 * step)
                    if m == 0 { break }
                    rayTable[d * 64 + s] |= m
                    step += 1
                }
            }
        }

        // 決まった種から作る。毎回同じ札になるので、不具合を再現しやすい
        var seed: UInt64 = 0x9E37_79B9_7F4A_7C15
        func next() -> UInt64 {   // splitmix64
            seed &+= 0x9E37_79B9_7F4A_7C15
            var z = seed
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            return z ^ (z >> 31)
        }
        let pieceTable = table(16 * 64), castleTable = table(16), epTable = table(8)
        for i in 0..<(16 * 64) { pieceTable[i] = next() }
        for i in 0..<16 { castleTable[i] = next() }
        for i in 0..<8 { epTable[i] = next() }

        knight = UnsafePointer(knightTable)
        king = UnsafePointer(kingTable)
        pawn = UnsafePointer(pawnTable)
        rays = UnsafePointer(rayTable)
        zobristPiece = UnsafePointer(pieceTable)
        zobristCastle = UnsafePointer(castleTable)
        zobristEpFile = UnsafePointer(epTable)
        zobristTurn = next()
    }

    /// 番号が増える向きの線。一番手前の駒まで（その駒を含む）
    @inline(__always)
    func rayUp(_ direction: Int, _ square: Int, _ occupied: UInt64) -> UInt64 {
        let line = rays[direction &* 64 &+ square]
        let blockers = line & occupied
        guard blockers != 0 else { return line }
        return line ^ rays[direction &* 64 &+ blockers.trailingZeroBitCount]
    }

    /// 番号が減る向きの線。一番手前の駒まで（その駒を含む）
    @inline(__always)
    func rayDown(_ direction: Int, _ square: Int, _ occupied: UInt64) -> UInt64 {
        let line = rays[direction &* 64 &+ square]
        let blockers = line & occupied
        guard blockers != 0 else { return line }
        return line ^ rays[direction &* 64 &+ (63 &- blockers.leadingZeroBitCount)]
    }

    @inline(__always)
    func rookAttacks(_ s: Int, _ occupied: UInt64) -> UInt64 {
        rayDown(Self.north, s, occupied) | rayUp(Self.south, s, occupied)
            | rayUp(Self.east, s, occupied) | rayDown(Self.west, s, occupied)
    }

    @inline(__always)
    func bishopAttacks(_ s: Int, _ occupied: UInt64) -> UInt64 {
        rayDown(Self.northEast, s, occupied) | rayDown(Self.northWest, s, occupied)
            | rayUp(Self.southEast, s, occupied) | rayUp(Self.southWest, s, occupied)
    }
}

// MARK: - キャスリング

/// キャスリング。4 つの条件を 1 つずつ確かめる。
///   1. まだ権利が残っている（キングもそのルークも一度も動いていない）
///   2. あいだのマスが空いている
///   3. 今チェックされていない
///   4. キングが通るマスと着くマスが攻められていない
/// 「ルークが攻められていてもよい」のが間違えやすいところ。条件はキングの通り道だけに掛かる。
private nonisolated struct ChessCastlePlan {
    let right: UInt8
    let flag: UInt8
    let king: Int, kingTo: Int, rook: Int, rookTo: Int
    let empty: UInt64
    let pass: (Int, Int, Int)

    private static func mask(_ squares: [Int]) -> UInt64 {
        squares.reduce(0) { $0 | (UInt64(1) << UInt64($1)) }
    }

    // キャスリングの権利はビットで持つ。K=1・Q=2・k=4・q=8
    static let whiteKing  = ChessCastlePlan(right: 1, flag: ChessMove.flagCastleK, king: 60, kingTo: 62, rook: 63, rookTo: 61,
                                            empty: mask([61, 62]), pass: (60, 61, 62))
    static let whiteQueen = ChessCastlePlan(right: 2, flag: ChessMove.flagCastleQ, king: 60, kingTo: 58, rook: 56, rookTo: 59,
                                            empty: mask([57, 58, 59]), pass: (60, 59, 58))
    static let blackKing  = ChessCastlePlan(right: 4, flag: ChessMove.flagCastleK, king: 4, kingTo: 6, rook: 7, rookTo: 5,
                                            empty: mask([5, 6]), pass: (4, 5, 6))
    static let blackQueen = ChessCastlePlan(right: 8, flag: ChessMove.flagCastleQ, king: 4, kingTo: 2, rook: 0, rookTo: 3,
                                            empty: mask([1, 2, 3]), pass: (4, 3, 2))
}

// MARK: - 決着

nonisolated struct ChessStatus: Equatable, Sendable {
    enum Kind: String, Sendable {
        case checkmate      // チェックメイト。winner 側の勝ち
        case stalemate      // ステイルメイト。指す手が無く、しかもチェックされていない
        case material       // どちらも詰ませられない駒しか残っていない
        case repetition     // 同じ局面が 3 回。主張できる（自動ではない）
        case repetition5    // 同じ局面が 5 回。自動で引き分け
        case fifty          // 50 手ルール。主張できる
        case seventyfive    // 75 手ルール。自動で引き分け
    }

    let over: Bool
    let kind: Kind?
    let winner: ChessColor?
    /// true なら、規則の上では「引き分けを主張できる」だけで、黙って指し続けることもできる。
    let claimable: Bool
}

// MARK: - 局面

nonisolated struct ChessPosition: Sendable {

    // 駒。見出しの説明を参照
    fileprivate(set) var pawns:   UInt64 = 0
    fileprivate(set) var knights: UInt64 = 0
    fileprivate(set) var bishops: UInt64 = 0
    fileprivate(set) var rooks:   UInt64 = 0
    fileprivate(set) var queens:  UInt64 = 0
    fileprivate(set) var kings:   UInt64 = 0
    fileprivate(set) var whites:  UInt64 = 0
    fileprivate(set) var blacks:  UInt64 = 0

    fileprivate(set) var turn: ChessColor = .white
    /// まだ残っているキャスリングの権利。K=1・Q=2・k=4・q=8
    fileprivate(set) var castleRights: UInt8 = 0
    /// アンパッサンで取れる通過マス。無ければ -1
    fileprivate(set) var enPassant: Int8 = -1
    /// 取りもポーンの動きもなかった連続手数（50 手ルール用）
    fileprivate(set) var halfMove: Int32 = 0
    /// 手数（黒が指し終えると 1 つ増える）
    fileprivate(set) var fullMove: Int32 = 1
    /// 局面の札。読みの置換表に使う
    fileprivate(set) var hash: UInt64 = 0

    static let startFen = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"
    static let emptyFen = "8/8/8/8/8/8/8/8 w - - 0 1"

    // MARK: 駒を見る

    @inline(__always) var occupied: UInt64 { whites | blacks }

    @inline(__always)
    func pieces(of color: ChessColor) -> UInt64 { color == .white ? whites : blacks }

    @inline(__always)
    func bitboard(of type: ChessPieceType) -> UInt64 {
        switch type {
        case .pawn:   return pawns
        case .knight: return knights
        case .bishop: return bishops
        case .rook:   return rooks
        case .queen:  return queens
        case .king:   return kings
        }
    }

    /// そのマスの駒の番号。空きなら ChessMove.none
    @inline(__always)
    fileprivate func pieceCode(at square: Int) -> UInt8 {
        let m = UInt64(1) << UInt64(truncatingIfNeeded: square)
        guard occupied & m != 0 else { return ChessMove.none }
        let color: UInt8 = whites & m != 0 ? 0 : 8
        if pawns & m != 0   { return color }
        if knights & m != 0 { return color | 1 }
        if bishops & m != 0 { return color | 2 }
        if rooks & m != 0   { return color | 3 }
        if queens & m != 0  { return color | 4 }
        return color | 5
    }

    func piece(at square: Int) -> ChessPiece? {
        let code = pieceCode(at: square)
        return code == ChessMove.none ? nil : ChessPiece(code: code)
    }

    /// キングのマス。いなければ -1（レッスンにはキングのいない盤がある）
    func findKing(_ color: ChessColor) -> Int {
        let k = kings & pieces(of: color)
        return k == 0 ? -1 : k.trailingZeroBitCount
    }

    // MARK: 盤を書き換える（中だけで使う）

    @inline(__always)
    private mutating func toggle(_ code: UInt8, _ square: Int, _ tables: ChessTables) {
        let m = UInt64(1) << UInt64(truncatingIfNeeded: square)
        switch code & 7 {
        case 0:  pawns ^= m
        case 1:  knights ^= m
        case 2:  bishops ^= m
        case 3:  rooks ^= m
        case 4:  queens ^= m
        default: kings ^= m
        }
        if code & 8 == 0 { whites ^= m } else { blacks ^= m }
        hash ^= tables.zobristPiece[Int(code) &* 64 &+ square]
    }

    /// 札を局面から作り直す。FEN を読んだときだけ使う。
    fileprivate mutating func recomputeHash() {
        let t = ChessTables.shared
        var h: UInt64 = 0
        for s in 0..<64 {
            let code = pieceCode(at: s)
            if code != ChessMove.none { h ^= t.zobristPiece[Int(code) * 64 + s] }
        }
        h ^= t.zobristCastle[Int(castleRights)]
        if enPassant >= 0 { h ^= t.zobristEpFile[Int(enPassant) & 7] }
        if turn == .black { h ^= t.zobristTurn }
        hash = h
    }

    // MARK: FEN

    init(fen: String = ChessPosition.startFen) {
        let parts = fen.split(whereSeparator: \.isWhitespace).map(String.init)
        let t = ChessTables.shared
        var i = 0
        for (row, text) in (parts.first ?? "").split(separator: "/", omittingEmptySubsequences: false).enumerated() where row < 8 {
            for ch in text {
                if let gap = ch.wholeNumberValue, (1...8).contains(gap) {
                    i += gap
                } else {
                    if i < 64, let piece = ChessPiece(fen: ch) { toggle(piece.code, i, t) }
                    i += 1
                }
            }
        }
        turn = parts.count > 1 && parts[1] == "b" ? .black : .white
        if parts.count > 2 {
            for ch in parts[2] {
                switch ch {
                case "K": castleRights |= 1
                case "Q": castleRights |= 2
                case "k": castleRights |= 4
                case "q": castleRights |= 8
                default:  break
                }
            }
        }
        if parts.count > 3, parts[3] != "-" { enPassant = Int8(ChessSquare.index(parts[3])) }
        halfMove = parts.count > 4 ? Int32(parts[4]) ?? 0 : 0
        fullMove = parts.count > 5 ? max(Int32(parts[5]) ?? 1, 1) : 1
        // アンパッサンの欄は、実際に取れる手が無くても FEN に書かれることがある。
        // 千日手の判定で局面の同一性に関わるため、取れないなら無かったことにする。
        if enPassant >= 0 && !enPassantIsReal() { enPassant = -1 }
        recomputeHash()
    }

    var fen: String {
        var rows: [String] = []
        for r in 0..<8 {
            var row = ""
            var gap = 0
            for c in 0..<8 {
                if let p = piece(at: r * 8 + c) {
                    if gap > 0 { row += String(gap); gap = 0 }
                    row.append(p.fen)
                } else {
                    gap += 1
                }
            }
            if gap > 0 { row += String(gap) }
            rows.append(row)
        }
        var castle = ""
        if castleRights & 1 != 0 { castle += "K" }
        if castleRights & 2 != 0 { castle += "Q" }
        if castleRights & 4 != 0 { castle += "k" }
        if castleRights & 8 != 0 { castle += "q" }
        let ep = enPassant >= 0 ? ChessSquare.name(Int(enPassant)) : "-"
        return "\(rows.joined(separator: "/")) \(turn == .white ? "w" : "b") "
            + "\(castle.isEmpty ? "-" : castle) \(ep) \(halfMove) \(fullMove)"
    }

    /// 手番だけを変えた局面。「相手は動かない」レッスンで、同じ色を続けて動かすのに使う。
    /// 手番が変わると札も変わるので、ここを通さず書き換えない。
    func withTurn(_ color: ChessColor) -> ChessPosition {
        guard color != turn else { return self }
        var next = self
        next.turn = color
        next.hash ^= ChessTables.shared.zobristTurn
        return next
    }

    // MARK: 千日手の見分け札

    /// 千日手を数えるための札。配置・手番・キャスリングの権利・アンパッサンの可能性まで含める。
    /// 手数は入れない（入れると同じ局面が二度と一致しない）。
    /// 64 ビットの hash で代用しないのは、衝突すると無実の局面が引き分けになるため。
    struct Key: Hashable, Sendable {
        let pawns, knights, bishops, rooks, queens, kings, whites, blacks: UInt64
        let turn: ChessColor
        let castleRights: UInt8
        let enPassant: Int8
    }

    var key: Key {
        Key(pawns: pawns, knights: knights, bishops: bishops, rooks: rooks, queens: queens,
            kings: kings, whites: whites, blacks: blacks,
            turn: turn, castleRights: castleRights, enPassant: enPassant)
    }

    // MARK: 利き

    /// そのマスは byColor に攻められているか。
    /// 調べたいマスから外へ向かって探す（「ここへ跳んでこられる位置にナイトがいるか」）。
    @inline(__always)
    func isAttacked(_ target: Int, by color: ChessColor) -> Bool {
        guard target >= 0 else { return false }
        let t = ChessTables.shared
        let theirs = pieces(of: color)
        if t.knight[target] & knights & theirs != 0 { return true }
        if t.king[target] & kings & theirs != 0 { return true }
        // 白のポーンが target を攻めるなら、target の黒の取り先に白のポーンがいる
        if t.pawn[Int(color.opposite.rawValue) &* 64 &+ target] & pawns & theirs != 0 { return true }
        let occ = occupied
        let straight = (rooks | queens) & theirs
        if straight != 0 && t.rookAttacks(target, occ) & straight != 0 { return true }
        let diagonal = (bishops | queens) & theirs
        if diagonal != 0 && t.bishopAttacks(target, occ) & diagonal != 0 { return true }
        return false
    }

    @inline(__always)
    func inCheck(_ color: ChessColor) -> Bool {
        let k = kings & pieces(of: color)
        guard k != 0 else { return false }
        return isAttacked(k.trailingZeroBitCount, by: color.opposite)
    }

    /// そのマスを攻めている駒の居場所の集まり。ピンは見ない。
    private func attackersMask(_ target: Int, by color: ChessColor) -> UInt64 {
        let t = ChessTables.shared
        let occ = occupied
        var m = t.knight[target] & knights
        m |= t.king[target] & kings
        m |= t.pawn[Int(color.opposite.rawValue) &* 64 &+ target] & pawns
        m |= t.rookAttacks(target, occ) & (rooks | queens)
        m |= t.bishopAttacks(target, occ) & (bishops | queens)
        return m & pieces(of: color)
    }

    /// そのマスを攻めている駒の居場所を全部返す。番号の小さい順。
    func attackers(of target: Int, by color: ChessColor) -> [Int] {
        var m = attackersMask(target, by: color)
        var out: [Int] = []
        while m != 0 {
            out.append(m.trailingZeroBitCount)
            m &= m &- 1
        }
        return out
    }

    // MARK: 手を作る

    /// 読みの 1 局面で作る手の上限より十分大きい数。
    /// 並べて遊ぶ盤ではクイーンを増やせるので、普通の局面の上限（218）より大きく取る。
    static let moveBufferCapacity = 1024

    @inline(__always)
    private func emit(_ out: UnsafeMutablePointer<ChessMove>, _ n: inout Int,
                      from: Int, to: Int, piece: UInt8,
                      promo: UInt8 = ChessMove.none, flags: UInt8 = 0) {
        let captured = pieceCode(at: to)
        out[n] = ChessMove(fromSquare: UInt8(truncatingIfNeeded: from), toSquare: UInt8(truncatingIfNeeded: to),
                           pieceCode: piece, capturedCode: captured,
                           capturedSquare: captured == ChessMove.none ? -1 : Int8(truncatingIfNeeded: to),
                           promoCode: promo, flags: flags)
        n &+= 1
    }

    @inline(__always)
    private func emitAll(_ out: UnsafeMutablePointer<ChessMove>, _ n: inout Int,
                         from: Int, targets: UInt64, piece: UInt8) {
        var m = targets
        while m != 0 {
            emit(out, &n, from: from, to: m.trailingZeroBitCount, piece: piece)
            m &= m &- 1
        }
    }

    /// ポーンが最終段に着いたら、なる駒 4 通りをそれぞれ別の手として作る。
    /// 「なる」をあとで選ばせる作りにすると、棋譜（e8=Q と e8=N）を書き分けられない。
    @inline(__always)
    private func emitPawn(_ out: UnsafeMutablePointer<ChessMove>, _ n: inout Int,
                          from: Int, to: Int, piece: UInt8) {
        if to < 8 || to >= 56 {
            emit(out, &n, from: from, to: to, piece: piece, promo: ChessPieceType.queen.rawValue)
            emit(out, &n, from: from, to: to, piece: piece, promo: ChessPieceType.rook.rawValue)
            emit(out, &n, from: from, to: to, piece: piece, promo: ChessPieceType.bishop.rawValue)
            emit(out, &n, from: from, to: to, piece: piece, promo: ChessPieceType.knight.rawValue)
        } else {
            emit(out, &n, from: from, to: to, piece: piece)
        }
    }

    private func addCastle(_ plan: ChessCastlePlan, _ color: ChessColor,
                           _ out: UnsafeMutablePointer<ChessMove>, _ n: inout Int) {
        guard castleRights & plan.right != 0 else { return }
        let mine = pieces(of: color)
        guard (kings & mine) >> UInt64(plan.king) & 1 != 0,
              (rooks & mine) >> UInt64(plan.rook) & 1 != 0,
              occupied & plan.empty == 0 else { return }
        let enemy = color.opposite
        guard !isAttacked(plan.pass.0, by: enemy),
              !isAttacked(plan.pass.1, by: enemy),
              !isAttacked(plan.pass.2, by: enemy) else { return }
        emit(out, &n, from: plan.king, to: plan.kingTo, piece: ChessPieceType.king.rawValue | (color.rawValue << 3),
             flags: plan.flag)
    }

    /// ルール違反を含む手を全部作る。自分のキングが取られる形かどうかは見ない。
    /// - Parameter capturesOnly: 取る手だけ作る（読みの静止探索用）
    /// - Returns: 作った手の数
    func pseudoMoves(for color: ChessColor, capturesOnly: Bool = false,
                     into out: UnsafeMutablePointer<ChessMove>) -> Int {
        let t = ChessTables.shared
        let own = pieces(of: color)
        let enemy = pieces(of: color.opposite)
        let occ = own | enemy
        let targets = capturesOnly ? enemy : ~own
        let colorCode = color.rawValue << 3
        var n = 0

        var bb = knights & own
        while bb != 0 {
            let s = bb.trailingZeroBitCount
            bb &= bb &- 1
            emitAll(out, &n, from: s, targets: t.knight[s] & targets, piece: colorCode | 1)
        }
        bb = bishops & own
        while bb != 0 {
            let s = bb.trailingZeroBitCount
            bb &= bb &- 1
            emitAll(out, &n, from: s, targets: t.bishopAttacks(s, occ) & targets, piece: colorCode | 2)
        }
        bb = rooks & own
        while bb != 0 {
            let s = bb.trailingZeroBitCount
            bb &= bb &- 1
            emitAll(out, &n, from: s, targets: t.rookAttacks(s, occ) & targets, piece: colorCode | 3)
        }
        bb = queens & own
        while bb != 0 {
            let s = bb.trailingZeroBitCount
            bb &= bb &- 1
            emitAll(out, &n, from: s,
                    targets: (t.rookAttacks(s, occ) | t.bishopAttacks(s, occ)) & targets,
                    piece: colorCode | 4)
        }
        bb = kings & own
        while bb != 0 {
            let s = bb.trailingZeroBitCount
            bb &= bb &- 1
            emitAll(out, &n, from: s, targets: t.king[s] & targets, piece: colorCode | 5)
        }

        // ポーン。前へ進むだけの手と、ななめに取る手で、行けるマスの決まり方が違う
        let up = color == .white ? -8 : 8
        let colorIndex = Int(color.rawValue)
        bb = pawns & own
        while bb != 0 {
            let s = bb.trailingZeroBitCount
            bb &= bb &- 1

            if !capturesOnly {
                let one = s &+ up
                if one >= 0 && one < 64 && occ >> UInt64(truncatingIfNeeded: one) & 1 == 0 {
                    emitPawn(out, &n, from: s, to: one, piece: colorCode)
                    // はじめの位置からだけ 2 マス。1 マス目が空いていることが前提
                    let isStart = color == .white ? (s >= 48 && s < 56) : (s >= 8 && s < 16)
                    if isStart {
                        let two = one &+ up
                        if occ >> UInt64(truncatingIfNeeded: two) & 1 == 0 {
                            emit(out, &n, from: s, to: two, piece: colorCode, flags: ChessMove.flagDouble)
                        }
                    }
                }
            }

            let hits = t.pawn[colorIndex &* 64 &+ s]
            var caps = hits & enemy
            while caps != 0 {
                emitPawn(out, &n, from: s, to: caps.trailingZeroBitCount, piece: colorCode)
                caps &= caps &- 1
            }

            // アンパッサン。取る駒は行き先ではなく、その 1 つ手前にいる
            if enPassant >= 0 {
                let ep = Int(enPassant)
                if hits >> UInt64(ep) & 1 != 0 && occ >> UInt64(ep) & 1 == 0 {
                    let victim = (s & 56) | (ep & 7)
                    let code = pieceCode(at: victim)
                    out[n] = ChessMove(fromSquare: UInt8(truncatingIfNeeded: s), toSquare: UInt8(ep),
                                       pieceCode: colorCode, capturedCode: code,
                                       capturedSquare: Int8(truncatingIfNeeded: victim),
                                       promoCode: ChessMove.none, flags: 0)
                    n &+= 1
                }
            }
        }

        if !capturesOnly && castleRights != 0 {
            if color == .white {
                addCastle(.whiteKing, color, out, &n)
                addCastle(.whiteQueen, color, out, &n)
            } else {
                addCastle(.blackKing, color, out, &n)
                addCastle(.blackQueen, color, out, &n)
            }
        }
        return n
    }

    /// 本当に指せる手。指してみて自分のキングが取られる形なら落とす。
    /// - Parameter color: 省略すると手番の側
    func legalMoves(for color: ChessColor? = nil) -> [ChessMove] {
        let c = color ?? turn
        return withUnsafeTemporaryAllocation(of: ChessMove.self, capacity: Self.moveBufferCapacity) { buffer in
            guard let base = buffer.baseAddress else { return [] }
            let count = pseudoMoves(for: c, into: base)
            var out: [ChessMove] = []
            out.reserveCapacity(count)
            for i in 0..<count where !leavesKingAttacked(base[i], c) {
                out.append(base[i])
            }
            return out
        }
    }

    @inline(__always)
    func leavesKingAttacked(_ move: ChessMove, _ color: ChessColor) -> Bool {
        var next = self
        next.apply(move)
        return next.inCheck(color)
    }

    /// あるマスの駒が指せる手だけ。盤を触ったときに行き先を光らせるのに使う。
    func moves(from square: Int) -> [ChessMove] {
        legalMoves().filter { $0.from == square }
    }

    /// アンパッサンの欄が飾りでないか（隣に取れるポーンが本当にいるか）。
    /// ピンで実際には取れない場合までは見ていない。千日手の札に使うだけなので十分。
    private func enPassantIsReal() -> Bool {
        guard enPassant >= 0 else { return false }
        let ep = Int(enPassant)
        let f = ChessSquare.file(ep), r = ChessSquare.rank(ep)
        // 白の通過マス（3 段目）なら、取るのは黒のポーン
        guard r == 3 || r == 6 else { return false }
        let takers = pawns & (r == 3 ? blacks : whites)
        let row = r == 3 ? 4 : 5
        for d in [-1, 1] {
            let s = ChessSquare.at(file: f + d, rank: row)
            if s >= 0 && takers >> UInt64(s) & 1 != 0 { return true }
        }
        return false
    }

    // MARK: 手を指す

    /// 手を指す。千日手の記録は付けない（遊ぶときは ChessGame.play を使う）。
    @inline(__always)
    mutating func apply(_ move: ChessMove) {
        let t = ChessTables.shared
        let from = move.from, to = move.to
        let pieceCode = move.pieceCode
        let color: ChessColor = pieceCode & 8 == 0 ? .white : .black
        let isPawn = pieceCode & 7 == 0
        let isKing = pieceCode & 7 == 5

        if move.capturedSquare >= 0 && move.capturedCode != ChessMove.none {
            toggle(move.capturedCode, Int(move.capturedSquare), t)
        }
        toggle(pieceCode, from, t)
        toggle(move.promoCode == ChessMove.none ? pieceCode : (move.promoCode | (pieceCode & 8)), to, t)

        // キャスリングはルークも一緒に動く
        if move.flags & (ChessMove.flagCastleK | ChessMove.flagCastleQ) != 0 {
            let plan: ChessCastlePlan
            if color == .white {
                plan = move.flags & ChessMove.flagCastleK != 0 ? .whiteKing : .whiteQueen
            } else {
                plan = move.flags & ChessMove.flagCastleK != 0 ? .blackKing : .blackQueen
            }
            let rook = ChessPieceType.rook.rawValue | (pieceCode & 8)
            toggle(rook, plan.rook, t)
            toggle(rook, plan.rookTo, t)
        }

        // キャスリングの権利は「減るだけ」。
        // 盤から作り直すと、キングが e1 に戻ってきたときに権利が復活してしまう
        var rights = castleRights
        if rights != 0 {
            if isKing { rights &= color == .white ? 0b1100 : 0b0011 }
            if from == 63 || to == 63 { rights &= ~1 }
            if from == 56 || to == 56 { rights &= ~2 }
            if from == 7  || to == 7  { rights &= ~4 }
            if from == 0  || to == 0  { rights &= ~8 }
            if rights != castleRights {
                hash ^= t.zobristCastle[Int(castleRights)] ^ t.zobristCastle[Int(rights)]
                castleRights = rights
            }
        }

        if enPassant >= 0 { hash ^= t.zobristEpFile[Int(enPassant) & 7] }
        enPassant = -1
        halfMove = (move.isCapture || isPawn) ? 0 : halfMove &+ 1
        if color == .black { fullMove &+= 1 }

        // 手番は「動かした駒の反対」。手番でない色を動かすレッスンでも同じ結果になる
        let nextTurn = color.opposite
        if nextTurn != turn {
            hash ^= t.zobristTurn
            turn = nextTurn
        }

        // 通過マスは、実際に取れるときだけ立てる。
        // 取れないのに立てておくと、千日手の判定で同じ局面を別物として数えてしまう
        if move.flags & ChessMove.flagDouble != 0 {
            enPassant = Int8(truncatingIfNeeded: (from &+ to) >> 1)
            if enPassantIsReal() {
                hash ^= t.zobristEpFile[Int(enPassant) & 7]
            } else {
                enPassant = -1
            }
        }
    }

    /// 手を指したあとの局面。元の局面は変わらない。
    func applying(_ move: ChessMove) -> ChessPosition {
        var next = self
        next.apply(move)
        return next
    }

    // MARK: 決着

    /// 詰ませる手が存在しない駒組みか。
    /// キング対キング・キング＋ナイト対キング・キング＋ビショップ対キング・
    /// 同じ色のマスのビショップ同士の 4 つだけを返す。根拠は chess.js の冒頭にある総当たり。
    /// ナイト 2 枚対キングは入れない。相手が最善を指さなければ詰む形があるため。
    var hasInsufficientMaterial: Bool {
        let rest = occupied & ~kings
        switch rest.nonzeroBitCount {
        case 0:
            return true
        case 1:
            return rest & (knights | bishops) != 0
        case 2:
            guard rest & bishops == rest else { return false }
            let a = rest.trailingZeroBitCount
            let b = (rest & (rest &- 1)).trailingZeroBitCount
            let differentColors = (whites >> UInt64(a) & 1) != (whites >> UInt64(b) & 1)
            return differentColors && ChessSquare.isLight(a) == ChessSquare.isLight(b)
        default:
            return false
        }
    }

    /// 決着の判定。
    /// - Parameter seen: いまの局面が現れた回数（千日手）。ChessGame が数えている
    func status(seen: Int = 0, moves: [ChessMove]? = nil) -> ChessStatus {
        let list = moves ?? legalMoves()
        if list.isEmpty {
            if inCheck(turn) {
                return ChessStatus(over: true, kind: .checkmate, winner: turn.opposite, claimable: false)
            }
            return ChessStatus(over: true, kind: .stalemate, winner: nil, claimable: false)
        }
        if hasInsufficientMaterial {
            return ChessStatus(over: true, kind: .material, winner: nil, claimable: false)
        }
        if seen >= 5 { return ChessStatus(over: true, kind: .repetition5, winner: nil, claimable: false) }
        if halfMove >= 150 { return ChessStatus(over: true, kind: .seventyfive, winner: nil, claimable: false) }
        if seen >= 3 { return ChessStatus(over: false, kind: .repetition, winner: nil, claimable: true) }
        if halfMove >= 100 { return ChessStatus(over: false, kind: .fifty, winner: nil, claimable: true) }
        return ChessStatus(over: false, kind: nil, winner: nil, claimable: false)
    }

    // MARK: 棋譜（SAN）

    /// 手を棋譜の 1 手に書く。Nf3・exd5・Bxc6+・Nbd2・O-O・e8=Q・Qh5#
    func san(of move: ChessMove) -> String {
        var text: String
        switch move.castle {
        case .kingSide:
            text = "O-O"
        case .queenSide:
            text = "O-O-O"
        case nil:
            let name = ChessSquare.name(move.to)
            if move.piece.type == .pawn {
                if move.isCapture {
                    text = "\(ChessSquare.name(move.from).prefix(1))x\(name)"
                } else {
                    text = name
                }
                if let promo = move.promotion { text += "=\(promo.letter)" }
            } else {
                text = "\(move.piece.type.letter)\(disambiguation(of: move))\(move.isCapture ? "x" : "")\(name)"
            }
        }
        let next = applying(move)
        if next.inCheck(next.turn) {
            text += next.legalMoves().isEmpty ? "#" : "+"
        }
        return text
    }

    /// 書き分け。比べる相手は「本当に指せる手」だけ。ピンで動けないもう 1 枚は数えない。
    ///   1. 出発した列が他と違えば、列だけ書く    Nbd2
    ///   2. 列が同じなら、段を書く                R1e2
    ///   3. どちらも同じなら、両方書く            Qh4e1
    private func disambiguation(of move: ChessMove) -> String {
        let rivals = legalMoves(for: move.piece.color)
            .filter { $0.to == move.to && $0.from != move.from && $0.piece.type == move.piece.type }
            .map(\.from)
        guard !rivals.isEmpty else { return "" }
        let sameFile = rivals.contains { ChessSquare.file($0) == ChessSquare.file(move.from) }
        let sameRank = rivals.contains { ChessSquare.rank($0) == ChessSquare.rank(move.from) }
        let name = ChessSquare.name(move.from)
        if !sameFile { return String(name.prefix(1)) }
        if !sameRank { return String(name.suffix(1)) }
        return name
    }

    /// 比べるために、意味の無い飾りを落とす。0-0 と O-O は同じものとして扱う。
    private static func normalizeSan(_ text: String) -> String {
        var s = text.trimmingCharacters(in: .whitespacesAndNewlines)
        s = s.replacingOccurrences(of: "[!?]+", with: "", options: .regularExpression)
        s = s.replacingOccurrences(of: "(?i)\\s*e\\.?p\\.?$", with: "", options: .regularExpression)
        s = s.replacingOccurrences(of: "[+#]", with: "", options: .regularExpression)
        s = s.replacingOccurrences(of: "0", with: "O")
        s = s.replacingOccurrences(of: "[–—−]", with: "-", options: .regularExpression)
        if s.uppercased() == "O-O-O" { return "O-O-O" }
        if s.uppercased() == "O-O" { return "O-O" }
        return s.replacingOccurrences(of: "-", with: "")
    }

    /// 棋譜の 1 手を読む。読めなければ nil。
    ///
    /// 文字を解析せず、合法手を全部作って SAN を書き、文字が一致するものを選ぶ。
    /// こうすると「書く」と「読む」が必ず同じ規則で動く。
    /// 長い書き方（Ng1-f3）と座標だけの書き方（g1f3・e7e8q）も受け取る。
    func parseSan(_ text: String) -> ChessMove? {
        let want = Self.normalizeSan(text)
        guard !want.isEmpty else { return nil }
        let all = legalMoves()
        if let match = all.first(where: { Self.normalizeSan(san(of: $0)) == want }) { return match }

        // 先頭の駒文字を先に落とす。なる駒のために n b r q を残すので、
        // 落とさないと Ng1-f3 の 'ng' をマスの名前として読もうとして失敗する
        let coord = want
            .replacingOccurrences(of: "^[KQRBNP]", with: "", options: .regularExpression)
            .lowercased()
            .replacingOccurrences(of: "[^a-h1-8qrbn]", with: "", options: .regularExpression)
        guard coord.count == 4 || coord.count == 5 else { return nil }
        let from = ChessSquare.index(String(coord.prefix(2)))
        let to = ChessSquare.index(String(coord.dropFirst(2).prefix(2)))
        let promo = coord.count == 5 ? ChessPieceType(letter: Character(String(coord.suffix(1)).uppercased())) : nil
        return all.first { m in
            guard m.from == from, m.to == to else { return false }
            guard let made = m.promotion else { return true }
            return made == (promo ?? .queen)   // 指定が無ければクイーン
        }
    }

    // MARK: 駒のねうちと、とりかえの損得（02 巻から使う）

    /// そのマスの駒のねうち。空きなら 0
    private func value(at square: Int) -> Int { piece(at: square)?.type.value ?? 0 }

    /// 取り合いの計算用に、駒をそのまま動かす。ルールは見ない。
    private mutating func slide(from: Int, to: Int) {
        let t = ChessTables.shared
        let target = pieceCode(at: to)
        if target != ChessMove.none { toggle(target, to, t) }
        let moved = pieceCode(at: from)
        toggle(moved, from, t)
        toggle(moved, to, t)
    }

    /// そのマスを攻めている駒のうち、いちばん安いものの居場所。無ければ -1。
    /// 同じねうちなら番号の小さいマス（chess.js が盤を順になめるのと同じ）。
    ///
    /// キングだけ条件が付く。取ったあとも相手がそのマスを攻めているなら取りに行けない。
    func cheapestAttacker(of target: Int, by color: ChessColor) -> Int {
        let m = attackersMask(target, by: color)
        if m == 0 { return -1 }
        if m & pawns != 0 { return (m & pawns).trailingZeroBitCount }
        if m & (knights | bishops) != 0 { return (m & (knights | bishops)).trailingZeroBitCount }
        if m & rooks != 0 { return (m & rooks).trailingZeroBitCount }
        if m & queens != 0 { return (m & queens).trailingZeroBitCount }
        let king = m.trailingZeroBitCount
        var after = self
        after.slide(from: king, to: target)
        return after.isAttacked(target, by: color.opposite) ? -1 : king
    }

    /// そのマスで取り合いを続けたときに、最後にいくら得するか（静的交換評価）。
    /// color が取り返す側。取り返さない自由があるので 0 と比べる。
    /// ピンで動かせない駒も数える。ここを読みにすると、答えの理由を人が追えなくなる。
    private func gainAfter(_ target: Int, _ color: ChessColor) -> Int {
        let from = cheapestAttacker(of: target, by: color)
        if from < 0 { return 0 }
        let taken = value(at: target)
        var next = self
        next.slide(from: from, to: target)
        return max(0, taken - next.gainAfter(target, color.opposite))
    }

    /// color がそのマスで取り始めたときの損得。得なら正、損なら負。取れないマスなら 0。
    func exchange(at target: Int, by color: ChessColor) -> Int {
        guard target >= 0, let piece = piece(at: target), piece.color != color else { return 0 }
        let from = cheapestAttacker(of: target, by: color)
        if from < 0 { return 0 }
        var next = self
        next.slide(from: from, to: target)
        // 最初の 1 回だけは「やめる自由」を掛けない。取りに行くと決めた手だから
        return piece.type.value - next.gainAfter(target, color.opposite)
    }

    /// その手で取りに行ったときの損得。exchange と違い「この駒で取ったら」を数える。
    func exchange(of move: ChessMove) -> Int {
        guard let captured = move.captured else { return 0 }
        var next = self
        if move.capturedAt >= 0 && move.capturedAt != move.to {   // アンパッサン
            next.toggle(move.capturedCode, move.capturedAt, ChessTables.shared)
        }
        next.slide(from: move.from, to: move.to)
        return captured.type.value - next.gainAfter(move.to, move.piece.color.opposite)
    }

    /// 残っている駒の合計。キングは数えない（交換できないため）。
    func material(of color: ChessColor) -> Int {
        let mine = pieces(of: color)
        return ChessPieceType.allCases.filter { $0 != .king }.reduce(0) {
            $0 + (bitboard(of: $1) & mine).nonzeroBitCount * $1.value
        }
    }
}

// MARK: - 対局

/// 1 局ぶんの状態。局面と、同じ局面が何回現れたか（千日手）を持つ。
/// 値型なので、「もどす」は手前の ChessGame を取っておくだけで済む。
nonisolated struct ChessGame: Sendable {
    private(set) var position: ChessPosition
    private var seen: [ChessPosition.Key: Int]

    init(fen: String = ChessPosition.startFen) {
        position = ChessPosition(fen: fen)
        seen = [position.key: 1]
    }

    /// 手を指す。
    mutating func play(_ move: ChessMove) {
        position.apply(move)
        seen[position.key, default: 0] += 1
    }

    /// いまの局面が現れた回数
    var seenCount: Int { seen[position.key] ?? 0 }

    /// その局面がこれまでに現れた回数
    func seenCount(of position: ChessPosition) -> Int { seen[position.key] ?? 0 }

    func status(moves: [ChessMove]? = nil) -> ChessStatus {
        position.status(seen: seenCount, moves: moves)
    }

    /// 棋譜の文字列を 1 手ずつ指していく結果。
    struct LineResult: Sendable {
        var game: ChessGame
        var moves: [ChessMove]
        var sans: [String]
        /// 読めなかった手の文字。最後まで読めたら nil
        var stopped: String?
    }

    /// 棋譜の文字列を 1 手ずつ指していく。読めない手が出たらそこで止める。
    func playingLine(_ line: String) -> LineResult {
        var text = line
        text = text.replacingOccurrences(of: "\\{[^}]*\\}", with: " ", options: .regularExpression)       // { } の注釈
        text = text.replacingOccurrences(of: "\\d+\\s*\\.(\\.\\.)?", with: " ", options: .regularExpression) // 1. や 1...
        text = text.replacingOccurrences(of: "(1-0|0-1|1/2-1/2|\\*)", with: " ", options: .regularExpression)
        var result = LineResult(game: self, moves: [], sans: [], stopped: nil)
        for token in text.split(whereSeparator: \.isWhitespace).map(String.init) {
            guard let move = result.game.position.parseSan(token) else {
                result.stopped = token
                return result
            }
            result.sans.append(result.game.position.san(of: move))
            result.moves.append(move)
            result.game.play(move)
        }
        return result
    }
}
