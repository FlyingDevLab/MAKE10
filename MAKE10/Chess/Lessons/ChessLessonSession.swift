//
//  ChessLessonSession.swift
//  FDL-TenBlitz
//
//  レッスン 1 回ぶんの進行。Web 版 chess-lessons.js の移植。
//  チェスのルールは書かない。ChessPosition が返した手しか盤に出さない。
//
// ★ 画面を知らない ★
//   SwiftUI に触らないので、全レッスンを画面と同じ操作で自動で解いて確かめられる。
//   音は sound で外へ知らせる。
//
// ★ 鍵も記録もご褒美もない ★
//   どのレッスンもいつでも開ける。読んで試すページなので、進んだ印も付けない。
//
// ★ 棋譜をまちがえた手は、盤に乗せない ★
//   いったん動かしてから戻すと、まちがいが一度 盤の上の事実になってしまい、
//   読み直すときに「どこまでが正しい形か」が分からなくなる。
//

import Foundation
import Observation

@Observable
final class ChessLessonSession {

    enum Tone { case plain, good, bad }
    enum Sound { case tap, capture, wrong, done }

    /// 待ち時間の倍率。自動の確認では 0 にする
    static var timeScale: Double = 1

    private enum C {
        static let blackPause: Double = 0.42   // 決まった返し・逃げるだけの回
        static let cpuPause: Double = 1.1      // 決まりごとの相手（おまけ）
        static let wrongFlash: Double = 0.32
    }

    /// もどすための控え
    private struct Snapshot {
        let game: ChessGame
        let record: [(san: String, color: ChessColor)]
        let lineAt: Int
        let chased: Int
        let ansAt: Int
        let last: (from: Int, to: Int)?
    }

    private struct Replay {
        var list: [ChessGame]
        var sans: [String]
        var moves: [ChessMove]
        var at = 0
    }

    let volume: ChessLessonVolume
    let hasNextVolume: Bool
    var sound: (Sound) -> Void = { _ in }

    let index: Int
    private(set) var setAt = 0

    private(set) var game = ChessGame()
    private var startGame = ChessGame()
    private var past: [Snapshot] = []
    private(set) var record: [(san: String, color: ChessColor)] = []
    private(set) var pick = -1
    private var askAt = 0
    private var hit: Set<String> = []
    private var lineAt = 0
    private(set) var hinted = false
    private(set) var held: String?
    private var placed: Set<Int> = []
    private var setupBoard: [ChessPiece?] = Array(repeating: nil, count: 64)
    private(set) var promotionChoices: [ChessMove] = []
    private var replay: Replay?
    private var chased = 0
    private var ansAt = 0
    private var last: (from: Int, to: Int)?
    private var wrong: Int?
    /// おまけの対局が終わった
    private(set) var isOver = false
    private(set) var isDone = false
    private(set) var isWaitingBlack = false
    private(set) var message = ""
    private(set) var tone = Tone.plain

    private var generation = 0

    init(volume: ChessLessonVolume, index: Int, hasNextVolume: Bool) {
        self.volume = volume
        self.index = index
        self.hasNextVolume = hasNextVolume
        restart()
    }

    // MARK: 読む

    var lesson: ChessLesson { volume.lessons[index] }
    private var goal: ChessLesson.Goal { lesson.goal }
    private var win: ChessLesson.Win? { goal.win }
    var kind: String { goal.kind }
    var isSetup: Bool { kind == "setup" }
    var isReplay: Bool { kind == "replay" }
    var isChase: Bool { kind == "chase" }
    var sets: [ChessLesson.PieceSet] { goal.sets ?? [] }
    var palette: [String] { goal.palette ?? [] }
    var hasPrevious: Bool { index > 0 }
    var hasNext: Bool { index < volume.lessons.count - 1 }
    var position: ChessPosition { game.position }

    private var startFen: String {
        if let sets = goal.sets, setAt < sets.count { return sets[setAt].fen }
        return lesson.fen
    }

    /// いま指すべき答え。無ければ nil。
    private var answerNow: String? {
        if let sets = goal.sets, setAt < sets.count, let answer = sets[setAt].answer { return answer }
        if let answers = win?.answers {
            guard ansAt % 2 == 0, ansAt < answers.count else { return nil }
            return answers[ansAt]
        }
        return win?.answer
    }

    var canHint: Bool { answerNow != nil }

    private var cpuOn: Bool { kind == "free" && goal.cpu == true }

    var pieces: [ChessPiece?] {
        isSetup ? setupBoard : (0..<64).map { position.piece(at: $0) }
    }

    private func say(_ en: String, _ ja: String, _ tone: Tone = .plain) {
        message = ChessText.pick(en, ja)
        self.tone = tone
    }

    private func clearSay() {
        message = ""
        tone = .plain
    }

    private func flashWrong(_ square: Int) {
        wrong = square
        sound(.wrong)
        let mine = generation
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(C.wrongFlash))
            guard let self, self.generation == mine else { return }
            self.wrong = nil
        }
    }

    private static func pieceName(_ type: ChessPieceType) -> String {
        switch type {
        case .pawn:   return ChessText.pick("pawn", "ポーン")
        case .knight: return ChessText.pick("knight", "ナイト")
        case .bishop: return ChessText.pick("bishop", "ビショップ")
        case .rook:   return ChessText.pick("rook", "ルーク")
        case .queen:  return ChessText.pick("queen", "クイーン")
        case .king:   return ChessText.pick("king", "キング")
        }
    }

    // MARK: 印

    /// 2 マスを結ぶ線。
    private func rayBetween(_ from: String, _ to: String) -> [Int] {
        let a = ChessSquare.index(from), b = ChessSquare.index(to)
        guard a >= 0, b >= 0 else { return [] }
        let df = ChessSquare.file(b) - ChessSquare.file(a)
        let dr = ChessSquare.rank(b) - ChessSquare.rank(a)
        if df != 0 && dr != 0 && abs(df) != abs(dr) { return [a, b] }
        var out: [Int] = []
        var file = ChessSquare.file(a), rank = ChessSquare.rank(a)
        for _ in 0..<8 {
            let at = ChessSquare.at(file: file, rank: rank)
            if at < 0 { break }
            out.append(at)
            if at == b { break }
            file += df.signum()
            rank += dr.signum()
        }
        return out
    }

    var marks: ChessBoardMarks {
        var out = ChessBoardMarks()
        out.wrong = wrong
        if let last { out.last = [last.from, last.to] }
        if !isSetup, canHint, hinted, let answer = answerNow, let move = position.parseSan(answer) {
            out.hint = move.from
        }
        if kind == "squares" { out.hit = Set(hit.map(ChessSquare.index)) }

        if let show = goal.show, isDone { out.line = Set(rayBetween(show[0], show[1])) }
        if kind == "squares" && goal.show != nil { return out }

        if kind == "squares" && !isDone {
            let asks = goal.ask ?? []
            let left: [String]
            if goal.ordered == true {
                left = askAt < asks.count ? [asks[askAt]] : []
            } else {
                left = asks.filter { !hit.contains($0) }
            }
            for name in left {
                let at = ChessSquare.index(name)
                if goal.mark == "frame" { out.askFiles.insert(ChessSquare.file(at)) }
                if goal.mark == "frame" || goal.mark == "rank" { out.askRanks.insert(ChessSquare.rank(at)) }
                if goal.mark == nil { out.ask.insert(at) }
            }
            return out
        }

        for name in lesson.goals ?? [] {
            let at = ChessSquare.index(name)
            if win?.capture?.contains(name) == true {
                if let p = position.piece(at: at), p.color != startGame.position.turn { out.goal.insert(at) }
            } else {
                out.goal.insert(at)
            }
        }

        if pick >= 0 {
            out.pick = pick
            out.goto = Set(allowedMoves(from: pick).map(\.to))
        }
        for color in [ChessColor.white, .black] where position.inCheck(color) {
            out.check = position.findKing(color)
        }
        return out
    }

    // MARK: 開始

    func choose(set newSet: Int) {
        guard newSet != setAt else { return }
        setAt = newSet
        restart()
    }

    func restart() {
        generation += 1
        startGame = ChessGame(fen: startFen)
        game = startGame
        past = []
        record = []
        pick = -1
        askAt = 0
        hit = []
        lineAt = 0
        held = nil
        hinted = false
        placed = []
        promotionChoices = []
        replay = nil
        chased = 0
        ansAt = 0
        last = nil
        wrong = nil
        isWaitingBlack = false
        isOver = false
        isDone = false
        setupBoard = (0..<64).map { game.position.piece(at: $0) }

        if isReplay { buildReplay() }

        if kind == "squares", goal.ordered == true, let first = goal.ask?.first {
            say("Find \(first).", "\(first)を さがして おしてみて。")
        } else if let first = win?.line?.first {
            say("Play this move: \(first)", "さいしょの 手は \(first)。")
        } else if isReplay {
            say("Start of the game.", "たいきょくの はじまり。")
        } else if isChase {
            say("You play White. Try to checkmate the black king.",
                "白が きみ。黒の キングを 詰ませられるか ためしてみよう。")
        } else {
            clearSay()
        }
    }

    // MARK: 押す

    func tap(square i: Int) {
        if isDone && !isChase { return }
        if isOver { return }
        switch kind {
        case "squares": answerSquare(i)
        case "setup":   placePiece(i)
        case "replay":  break
        default:        touchPiece(i)
        }
    }

    private func answerSquare(_ i: Int) {
        let name = ChessSquare.name(i)
        let asks = goal.ask ?? []

        if goal.ordered == true {
            guard askAt < asks.count else { return }
            let want = asks[askAt]
            if name != want {
                flashWrong(i)
                say("That is \(name). Look for \(want).", "そこは \(name)。さがして いるのは \(want)。", .bad)
                return
            }
            askAt += 1
            hit.insert(name)
            sound(.tap)
            if askAt >= asks.count {
                let all = asks.count > 1
                say("Yes, \(name)." + (all ? " That is all \(asks.count)." : ""),
                    "せいかい。" + (all ? "\(asks.count)つ ぜんぶ。" : ""), .good)
                finish()
                return
            }
            say("Yes, \(name).", "せいかい。つぎは \(asks[askAt])。", .good)
            return
        }

        guard asks.contains(name) else {
            flashWrong(i)
            say("Not \(name).", "\(name)は ちがうよ。", .bad)
            return
        }
        if hit.contains(name) {
            say("\(name) is already done.", "\(name)は もう おしたよ。")
            return
        }
        hit.insert(name)
        sound(.tap)
        let left = asks.filter { !hit.contains($0) }.count
        var tailEn = "", tailJa = ""
        if left > 0 {
            tailEn = " \(left) to go."
            tailJa = "あと \(left)つ。"
        } else if asks.count > 1 {
            tailEn = " That is all \(asks.count)."
            tailJa = "\(asks.count)つ ぜんぶ。"
        }
        if goal.say == "value", let piece = position.piece(at: i) {
            let worth = piece.type == .king ? "♾️" : String(piece.type.value)
            let name = Self.pieceName(piece.type)
            say("\(name) = \(worth).\(tailEn)", "\(name)は \(worth)。\(tailJa)", .good)
        } else {
            say("Yes, \(name).\(tailEn)", "せいかい。\(tailJa)", .good)
        }
        if left == 0 { finish() }
    }

    // MARK: 並べる

    /// そのこまを あと何枚おけるか
    func left(of letter: String) -> Int {
        guard let want = goal.want else { return 0 }
        let position = ChessPosition(fen: want)
        var need = 0, have = 0
        for i in 0..<64 {
            if position.piece(at: i).map({ String($0.fen) }) == letter { need += 1 }
            if placed.contains(i), setupBoard[i].map({ String($0.fen) }) == letter { have += 1 }
        }
        return need - have
    }

    func hold(_ letter: String) {
        guard left(of: letter) > 0 else { return }
        sound(.tap)
        held = held == letter ? nil : letter
    }

    private func placePiece(_ i: Int) {
        if placed.contains(i) {
            setupBoard[i] = nil
            placed.remove(i)
            sound(.tap)
            clearSay()
            return
        }
        guard let held else {
            say("Pick a piece from the shelf first.", "まず 下から こまを えらんでね。")
            return
        }
        if setupBoard[i] != nil { return }
        guard let letter = held.first, let piece = ChessPiece(fen: letter) else { return }
        guard left(of: held) > 0 else {
            say("No more \(Self.pieceName(piece.type)) to place.", "\(Self.pieceName(piece.type))は もう ぜんぶ おいたよ。")
            return
        }
        setupBoard[i] = piece
        placed.insert(i)
        sound(.tap)

        if placed.count >= 8, let wantFen = goal.want {
            let want = ChessPosition(fen: wantFen)
            let same = (0..<64).allSatisfy { want.piece(at: $0) == setupBoard[$0] }
            if same {
                finish()
            } else {
                say("All eight are down, but not all in the right place.",
                    "8まい おけたけど、どこかが ちがう。クイーンは 白マスの d1 だよ。", .bad)
            }
            return
        }
        clearSay()
    }

    // MARK: 指す

    private func isAllowed(_ move: ChessMove) -> Bool {
        guard let only = lesson.only else { return true }
        return String(move.piece.type.letter) == only
    }

    private func allowedMoves(from square: Int) -> [ChessMove] {
        position.moves(from: square).filter(isAllowed)
    }

    private func touchPiece(_ i: Int) {
        guard promotionChoices.isEmpty, !isWaitingBlack else { return }
        if pick >= 0 {
            if allowedMoves(from: pick).contains(where: { $0.to == i }) {
                tryMove(pick, i)
                return
            }
            if i == pick {
                pick = -1
                clearSay()
                return
            }
        }
        guard let piece = position.piece(at: i) else {
            pick = -1
            clearSay()
            return
        }
        if piece.color != position.turn {
            say("It is \(position.turn == .white ? "White" : "Black") to move.",
                "いまは \(position.turn == .white ? "白" : "黒")の てばんだよ。")
            return
        }
        if let only = lesson.only, String(piece.type.letter) != only,
           let onlyType = ChessPieceType(letter: Character(only)) {
            say("Move the \(Self.pieceName(onlyType)) in this lesson.",
                "この レッスンは \(Self.pieceName(onlyType))を うごかす れんしゅう。")
            return
        }
        pick = i
        sound(.tap)
        if allowedMoves(from: i).isEmpty {
            say("That \(Self.pieceName(piece.type)) has nowhere to go.",
                "その \(Self.pieceName(piece.type))は、いま どこへも 行けない。")
        } else {
            clearSay()
        }
    }

    private func tryMove(_ from: Int, _ to: Int) {
        let list = allowedMoves(from: from).filter { $0.to == to }
        guard let first = list.first else { return }
        if list.count > 1, first.promotion != nil {
            // 棋譜どおりに指す回は、なる駒を棋譜が決めている
            if let line = win?.line, lineAt < line.count,
               let range = line[lineAt].range(of: "=[QRBN]", options: .regularExpression),
               let letter = line[lineAt][range].last,
               let type = ChessPieceType(letter: letter),
               let move = list.first(where: { $0.promotion == type }) {
                doMove(move)
                return
            }
            promotionChoices = list
            say("Choose what the pawn becomes.", "ポーンが なる こまを えらんで。")
            return
        }
        doMove(first)
    }

    func choosePromotion(_ move: ChessMove) {
        promotionChoices = []
        doMove(move)
    }

    private static func sameSan(_ a: String, _ b: String) -> Bool {
        let strip: (String) -> String = { $0.filter { !"+#!?".contains($0) } }
        return strip(a) == strip(b)
    }

    private func tellWrong(_ move: ChessMove, _ san: String) {
        if move.isCapture {
            let value = position.exchange(of: move)
            if value < 0 {
                say("\(san) loses \(-value) — it gets taken back.", "\(san)は とりかえされて \(-value) そんするよ。", .bad)
            } else if value == 0 {
                say("\(san) is an even trade.", "\(san)は とりかえっこ。とくには ならないよ。", .bad)
            } else {
                say("That wins something, but there is more.", "とくは するけど、もっと いい手が あるよ。", .bad)
            }
            return
        }
        if let answer = answerNow, let right = position.parseSan(answer), right.isCapture {
            say("Not that move. Look at what you can take.", "ちがう手だよ。とれる こまを 見てみて。", .bad)
            return
        }
        say("Not that move. Read the task again and look at the whole board.",
            "ちがう手だよ。やる ことを もう一度 読んで、盤ぜんたいを 見てみて。", .bad)
    }

    /// 手を盤に乗せて、棋譜に積み、音を鳴らす。
    private func commit(_ move: ChessMove) {
        past.append(Snapshot(game: game, record: record, lineAt: lineAt, chased: chased, ansAt: ansAt, last: last))
        record.append((position.san(of: move), position.turn))
        game.play(move)
        last = (move.from, move.to)
        sound(move.isCapture ? .capture : .tap)
    }

    private func doMove(_ move: ChessMove) {
        if let want = answerNow {
            let tried = position.san(of: move)
            if !Self.sameSan(tried, want) {
                flashWrong(move.to)
                tellWrong(move, tried)
                pick = -1
                return
            }
        }
        if let line = win?.line, lineAt < line.count {
            let wanted = line[lineAt]
            let got = position.san(of: move)
            if !Self.sameSan(got, wanted) {
                flashWrong(move.to)
                say("The notation says \(wanted). That move is \(got).", "きふは \(wanted)。いま さそうと したのは \(got)。", .bad)
                pick = -1
                return
            }
        }

        var way: String?
        if win?.escape == true, position.inCheck(position.turn) {
            let checkers = position.attackers(of: position.findKing(position.turn), by: position.turn.opposite)
            if move.piece.type == .king {
                way = "king"
            } else if checkers.contains(move.to) {
                way = "capture"
            } else {
                way = "block"
            }
        }

        let before = position.turn
        commit(move)
        if lesson.still == true { game.setTurn(before) }
        pick = -1
        promotionChoices = []
        if win?.line != nil { lineAt += 1 }
        clearSay()
        judge(move, way)
    }

    private func hasFlag(_ move: ChessMove, _ flag: String) -> Bool {
        switch flag {
        case "promo":   return move.promotion != nil
        case "ep":      return move.capturedAt >= 0 && move.capturedAt != move.to
        case "castleK": return move.castle == .kingSide
        case "castleQ": return move.castle == .queenSide
        default:        return false
        }
    }

    private func judge(_ move: ChessMove, _ way: String?) {
        let startTurn = startGame.position.turn

        if isChase {
            chased += 1
            if position.legalMoves().isEmpty {
                chaseReport()
                return
            }
            letBlackRun(nil)
            return
        }

        if kind == "free" {
            reportFree()
            if cpuOn && position.turn == .black && !isOver { letBlackRun(move) }
            return
        }

        if let answers = win?.answers {
            sayNote(ansAt)
            ansAt += 1
            if ansAt >= answers.count {
                finish()
                return
            }
            letBlackRun(nil)
            return
        }

        if answerNow != nil {
            finish()
            return
        }

        guard let win else {
            clearSay()
            return
        }

        if let line = win.line {
            if lineAt >= line.count {
                finish()
                return
            }
            say("Next: \(line[lineAt])", "つぎは \(line[lineAt])。", .good)
            return
        }

        if let capture = win.capture {
            let left = capture.filter {
                position.piece(at: ChessSquare.index($0)).map { $0.color != startTurn } ?? false
            }
            if left.isEmpty {
                finish()
                return
            }
            if move.isCapture {
                say("Taken. \(left.count) to go.", "とれた。あと \(left.count)つ。", .good)
            } else {
                clearSay()
            }
            return
        }

        if let reach = win.reach {
            let all = reach.allSatisfy {
                position.piece(at: ChessSquare.index($0)).map { $0.color == startTurn } ?? false
            }
            if all { finish() } else { clearSay() }
            return
        }

        if let flag = win.flag {
            if move.piece.color == startTurn && hasFlag(move, flag) {
                finish()
                return
            }
            if flag == "promo" {
                say("Get the pawn to the last rank.", "ポーンを いちばん おくの だんまで すすめよう。")
            } else if flag == "castleK" {
                say("Move the king two squares toward the rook.", "キングを ルークの ほうへ 2マス うごかしてみて。")
            } else {
                clearSay()
            }
            return
        }

        if let status = win.status {
            let now = game.status()
            if now.kind?.rawValue == status {
                finish()
            } else if now.kind == .checkmate {
                say("That is checkmate, not stalemate.", "それは チェックメイト。ステイルメイトは チェックに しない 手。", .bad)
            } else if position.inCheck(position.turn) {
                say("That is a check. Try a move that gives no check.", "それは チェック。チェックに ならない 手を さがしてみて。", .bad)
            } else {
                say("Not yet. Press Undo and try another move.", "まだ ちがう。「もどす」で 1手 もどして、べつの 手を ためしてみて。", .bad)
            }
            return
        }

        if win.escape == true {
            if !position.inCheck(startTurn) {
                let labels: [String: (String, String)] = [
                    "king": ("moved the king", "キングが にげた"),
                    "block": ("blocked the line", "あいだに 入った"),
                    "capture": ("took the attacker", "ねらって いる こまを とった"),
                ]
                if let way, let label = labels[way] {
                    say("Out of check — you \(label.0).", "チェックから にげられた。つかったのは「\(label.1)」。", .good)
                }
                finish()
            }
            return
        }
        clearSay()
    }

    private func sayNote(_ i: Int) {
        if let notes = win?.notes, notes.indices.contains(i), let note = notes[i] { say(note.en, note.ja, .good) }
    }

    // MARK: 相手

    /// 「次に自分が動ける数がいちばん多い所へ」逃げる。
    /// 動ける数を見るのは、ステイルメイトで課題が途中で終わらないようにするため。
    private func fleeMove() -> ChessMove? {
        let list = position.legalMoves()
        guard !list.isEmpty else { return nil }
        let whiteKing = position.findKing(.white)
        var best: ChessMove?
        var bestScore = -Double.infinity
        for move in list {
            let next = position.applying(move)
            let room = next.legalMoves(for: move.piece.color).count
            let away = max(abs(ChessSquare.file(move.to) - ChessSquare.file(whiteKing)),
                           abs(ChessSquare.rank(move.to) - ChessSquare.rank(whiteKing)))
            let edge = max(abs(Double(ChessSquare.file(move.to)) - 3.5), abs(Double(ChessSquare.rank(move.to)) - 4.5))
            let score = Double(room) * 100 + Double(away) * 10 - edge * 6
            // 同点なら行き先の番号が小さい手。手の並びで答えが変わらないように
            if score > bestScore || (score == bestScore && move.to < (best?.to ?? 64)) {
                bestScore = score
                best = move
            }
        }
        return best
    }

    private func letBlackRun(_ lastMove: ChessMove?) {
        isWaitingBlack = true
        let mine = generation
        let pause = kind == "free" ? C.cpuPause : C.blackPause
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(pause * Self.timeScale))
            guard let self, self.generation == mine else { return }
            self.isWaitingBlack = false
            self.runBlack(lastMove)
        }
    }

    private func runBlack(_ lastMove: ChessMove?) {
        if kind == "moves", let answers = win?.answers {
            guard ansAt < answers.count, let move = position.parseSan(answers[ansAt]) else { return }
            commit(move)
            sayNote(ansAt)
            ansAt += 1
            return
        }
        if kind == "free" {
            guard let move = ChessCPU.choose(position, lastMove: lastMove) else {
                reportFree()
                return
            }
            commit(move)
            reportFree()
            return
        }
        guard isChase else { return }
        guard let move = fleeMove() else {
            chaseReport()
            return
        }
        commit(move)
        chaseReport()
    }

    private func chaseReport() {
        let want = goal.moves ?? 0
        let left = want - chased
        if game.status().kind == .stalemate {
            say("Stalemate — a draw. Still not checkmate.", "ステイルメイト。これも ひきわけ。チェックメイトでは ない。", .good)
            finish()
            return
        }
        let hasOwnPiece = position.whites & ~position.kings != 0
        if !hasOwnPiece {
            say("Your piece was taken — it stood next to the king unprotected.",
                "こまを とられて しまった。キングの となりに おくと とられる。キングだけに なったら、なおさら 詰ませられない。「やりなおす」で もう一度。", .bad)
            if left <= 0 && !isDone { finish() }
            return
        }
        if left <= 0 {
            say("Still no checkmate. There is no way to make one.",
                "\(chased)手 さしても 詰まない。じつは どう ならべても 詰む かたちが ない。", .good)
            if !isDone { finish() }
            return
        }
        if position.inCheck(.black) {
            say("Check — but the king just walks away. \(left) to go.", "チェック。でも キングは よけて いく。あと \(left)手。")
            return
        }
        say("No checkmate yet. \(left) to go.", "まだ 詰まない。あと \(left)手。")
    }

    /// おまけ：盤の状態を一言で伝える（決着・チェック・ひきわけ）。
    private func reportFree() {
        let status = game.status()
        if status.over || status.claimable { isOver = true }
        switch status.kind {
        case .checkmate:
            let white = status.winner == .white
            say("Checkmate. \(white ? "White" : "Black") wins.", "チェックメイト。\(white ? "白" : "黒")の かち。", .good)
        case .stalemate:
            say("Stalemate. A draw.", "ステイルメイト。ひきわけ。", .good)
        case .material:
            say("Neither side can mate. A draw.", "もう どちらも 詰ませられない。ひきわけ。", .good)
        case .repetition, .repetition5:
            say("The same position came up three times. A draw.", "おなじ ばんめんに 3かい なった。ひきわけ。", .good)
        case .fifty, .seventyfive:
            say("Fifty moves with no pawn moved and nothing taken. A draw.", "50手の あいだ、ポーンも うごかず こまも とられなかった。ひきわけ。", .good)
        case nil:
            if position.inCheck(position.turn) {
                say("Check.", "チェック。\(position.turn == .white ? "白" : "黒")の キングが ねらわれて いる。")
            } else {
                clearSay()
            }
        }
    }

    // MARK: 棋譜を見る

    private func buildReplay() {
        let result = startGame.playingLine(goal.line ?? "")
        var list = [startGame]
        var current = startGame
        for move in result.moves {
            current.play(move)
            list.append(current)
        }
        replay = Replay(list: list, sans: result.sans, moves: result.moves)
    }

    var replayCanGoBack: Bool { (replay?.at ?? 0) > 0 }
    var replayCanGoForward: Bool {
        guard let replay else { return false }
        return replay.at < replay.list.count - 1
    }

    func replayGo(_ step: Int) {
        guard var rp = replay else { return }
        let at = rp.at + step
        guard rp.list.indices.contains(at) else { return }
        rp.at = at
        replay = rp
        game = rp.list[at]
        last = at > 0 ? (rp.moves[at - 1].from, rp.moves[at - 1].to) : nil
        if step > 0 && at > 0 { sound(rp.moves[at - 1].isCapture ? .capture : .tap) }
        record = (0..<at).map { (rp.sans[$0], $0 % 2 == 0 ? ChessColor.white : .black) }

        if at == 0 {
            say("Start of the game.", "たいきょくの はじまり。")
        } else {
            let number = (at - 1) / 2 + 1
            let who = at % 2 == 1 ? "白" : "黒"
            say("\(number). \(rp.sans[at - 1])", "\(number)手め、\(who)が \(rp.sans[at - 1])。")
        }
        if at == rp.list.count - 1 {
            let status = game.status()
            if status.kind == .checkmate {
                let white = status.winner == .white
                let result = white ? "1-0" : "0-1"
                say("Checkmate — \(white ? "White" : "Black") wins. \(result)",
                    "チェックメイト。\(white ? "白" : "黒")の かち。きふの さいごは \(result)。", .good)
            }
        }
    }

    // MARK: もどす・ヒント

    var canUndo: Bool { !past.isEmpty && !isReplay }

    func undo() {
        guard canUndo else { return }
        generation += 1
        isWaitingBlack = false
        wrong = nil       // 消す合図の待ちも止まるので、ここで消す
        sound(.tap)
        guard var back = past.popLast() else { return }
        // 相手の手と自分の手が 1 組で 1 手に見える回は、1 つだけ戻すと相手の手番で止まる
        let pairs = isChase || cpuOn || win?.answers != nil
        if pairs && !past.isEmpty && back.game.position.turn != startGame.position.turn, let earlier = past.popLast() {
            back = earlier
        }
        game = back.game
        record = back.record
        lineAt = back.lineAt
        chased = back.chased
        ansAt = back.ansAt
        last = back.last
        pick = -1
        promotionChoices = []
        isOver = false
        isDone = false
        clearSay()
    }

    func showHint() {
        guard canHint else { return }
        hinted = true
        sound(.tap)
        say("Move this piece.", "この こまを うごかすよ。")
    }

    // MARK: できた

    /// 巻の最後の課題か。後ろに自由に指す回や棋譜を見る回しか残っていなければ最後とする。
    var isLastTask: Bool {
        !volume.lessons[(index + 1)...].contains { !["free", "replay"].contains($0.goal.kind) }
    }

    private func finish() {
        isDone = true
        pick = -1
        promotionChoices = []
        sound(.done)
    }

    /// 決着の書き方。まだなら空。
    private var resultText: String {
        let status = game.status()
        if isOver {
            if status.winner == .white { return "1-0" }
            if status.winner == .black { return "0-1" }
            return "1/2-1/2"
        }
        switch status.kind {
        case .checkmate:                             return status.winner == .white ? "1-0" : "0-1"
        case .stalemate, .material, .repetition5, .seventyfive: return "1/2-1/2"
        default:                                     return ""
        }
    }

    /// 棋譜の文字に、決着の書き方を足したもの。
    var recordText: String {
        let text = ChessNotation.text(record, firstNumber: Int(startGame.position.fullMove))
        return text.isEmpty || resultText.isEmpty ? text : "\(text) \(resultText)"
    }
}

/// 盤に付ける印。マスは 0〜63 の番号。
struct ChessBoardMarks {
    /// 持ち上げている駒
    var pick: Int?
    /// 行ける先
    var goto: Set<Int> = []
    /// 直前に指した手
    var last: Set<Int> = []
    /// チェックされているキング
    var check: Int?
    /// 課題の的
    var goal: Set<Int> = []
    /// 「ここを押して」
    var ask: Set<Int> = []
    /// 押せたマス
    var hit: Set<Int> = []
    /// 答えの理由になっている線
    var line: Set<Int> = []
    /// ヒント（動かす駒）
    var hint: Int?
    /// まちがえたマス
    var wrong: Int?
    /// 名前を光らせる筋（0 = a）と段（1〜8）
    var askFiles: Set<Int> = []
    var askRanks: Set<Int> = []
}
