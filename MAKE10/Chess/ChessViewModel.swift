//
//  ChessViewModel.swift
//  FDL-TenBlitz
//
//  チェスの「あそぶ」の進行。コンピュータと・ふたりで・ならべての 3 つのモードを 1 つで持つ。
//  ルールは ChessEngine、相手の手は ChessAI が決める。ここにチェスのルールは書かない。
//
// ★ init で対局を動かさない ★
//   SwiftUI は @State の初期値を何度も作って捨てることがある。
//   init は保存を読むだけにして、相手を動かすのは画面が出てから（appear）にする。
//
// ★ 段が動く・報酬が出るのは「コンピュータ」モードだけ ★
//   「ならべて」のコンピュータ戦は、詰む直前の形を並べて勝てるので、どちらも動かさない。
//
// ★ コンピュータ戦は、決着のあとに「もどす」を使えない ★
//   Web 版は使えるが、もどして勝ち直すと報酬を何度も取れてしまう。
//
// ★ 決着の処理と保存の削除は同じ流れの中で済ませる ★
//   途中で分けると、報酬を渡したあとでアプリが終わったときに、
//   保存が残って同じ勝ちをもう一度受け取れる形になる。
//

import SwiftUI

// MARK: - 止めるための札

/// 裏で考えている相手に「もう要らない」と伝える札。
private nonisolated final class ChessStopFlag: @unchecked Sendable {
    var isStopped = false
}

// MARK: - ChessViewModel

@Observable
final class ChessViewModel {

    enum Mode: String, CaseIterable, Identifiable {
        case computer, twoPlayers, sandbox
        var id: String { rawValue }

        var label: LocalizedStringKey {
            switch self {
            case .computer:   return "chess_mode_computer"
            case .twoPlayers: return "chess_mode_two"
            case .sandbox:    return "chess_mode_sandbox"
            }
        }
    }

    enum Phase {
        case choosingColor   // コンピュータ戦の色を選んでいる
        case arranging       // 「ならべて」で駒を並べている
        case playing
        case finished
    }

    enum Ending: Equatable {
        case checkmate(winner: ChessColor)
        case stalemate
        case material
        case repetition
        case fifty
        case resigned
    }

    private enum C {
        /// 考える相手の、1 手の合計の間（秒）。速すぎると、黒が動いたのかどうかが分からない
        static let computerTotal: Double = 1.5
        /// 考え終わってから指すまでの、最低限の間（秒）
        static let computerMinimum: Double = 0.25
        /// 投了の「ほんとうに？」が、ひとりでに戻るまで（秒）
        static let confirmWait: Double = 5
    }

    // MARK: 状態

    private(set) var mode: Mode
    private(set) var phase: Phase = .playing
    private(set) var game = ChessGame()
    private(set) var sans: [String] = []
    private(set) var lastMove: ChessMove?
    private(set) var selected: Int?
    private(set) var targets: [ChessMove] = []
    /// プロモーションで選ぶ手。空でなければ、なる駒を聞いている
    private(set) var promotionChoices: [ChessMove] = []
    private(set) var isThinking = false
    private(set) var ending: Ending?
    private(set) var playerColor: ChessColor = .white
    private(set) var vsComputer = false
    /// 投了・はじめからを 1 回押して、確認を待っている
    private(set) var isConfirming = false

    // 「ならべて」
    private(set) var arranged: [ChessPiece?] = Array(repeating: nil, count: 64)
    private(set) var held: ChessPiece?
    /// 並べ方が決まりに合わないときの知らせ
    private(set) var arrangeNotice: LocalizedStringKey?

    private var startFen = ChessPosition.startFen
    private var moves: [ChessMove] = []
    private var past: [ChessGame] = []
    private var thinkTask: Task<Void, Never>?
    private var stopFlag: ChessStopFlag?
    private var confirmTask: Task<Void, Never>?

    // MARK: 開始

    init(mode: Mode) {
        self.mode = mode
        if let saved = ChessStore.saved(for: mode), restore(saved) { return }
        showFirstPhase()
    }

    /// 1 局ぶんの記録を空にする。
    private func resetBoardState() {
        ending = nil
        lastMove = nil
        sans = []
        moves = []
        past = []
        clearSelection()
    }

    /// 保存のない状態の最初の画面。
    private func showFirstPhase() {
        resetBoardState()
        cancelConfirm()
        switch mode {
        case .computer:
            game = ChessGame()
            startFen = ChessPosition.startFen
            vsComputer = true
            playerColor = ChessStore.lastColor
            phase = .choosingColor
        case .twoPlayers:
            startGame(fen: ChessPosition.startFen, vsComputer: false, color: .white)
        case .sandbox:
            vsComputer = false
            playerColor = .white
            phase = .arranging
        }
    }

    /// 保存から戻す。読めなければ false。
    private func restore(_ saved: ChessSavedGame) -> Bool {
        playerColor = ChessColor(fenLetter: saved.playerColor)
        vsComputer = saved.vsComputer
        startFen = saved.startFen
        if saved.isArranging {
            load(arrangement: saved.startFen)
            phase = .arranging
            return true
        }
        var replay = ChessGame(fen: saved.startFen)
        var history: [ChessGame] = []
        var played: [ChessMove] = []
        var text: [String] = []
        for coordinate in saved.moves {
            guard let move = replay.position.legalMoves().first(where: { $0.coordinate == coordinate }) else {
                return false
            }
            history.append(replay)
            text.append(replay.position.san(of: move))
            played.append(move)
            replay.play(move)
        }
        game = replay
        past = history
        moves = played
        sans = text
        lastMove = played.last
        phase = .playing
        // 終わった局が残っているのは、ふたりで指して、決着のあとに閉じたときだけ
        let status = game.status()
        if status.over || status.claimable { ending = Self.ending(from: status); phase = .finished }
        return true
    }

    /// 画面が出たときに呼ぶ。
    func appear() {
        EnergyStore.shared.beginSession()   // 結果に出す「今回の獲得量」を 0 に戻す
        continueComputerIfNeeded()
    }

    /// 画面が消えるときに呼ぶ。考えている途中なら止める（保存は 1 手ごとに済んでいる）。
    func disappear() {
        cancelThinking()
        cancelConfirm()
    }

    /// 開いたときに相手の番なら、考え始める（考えている途中で閉じたとき）。
    private func continueComputerIfNeeded() {
        guard phase == .playing, vsComputer, game.position.turn != playerColor, !isThinking else { return }
        letComputerMove()
    }

    private func startGame(fen: String, vsComputer: Bool, color: ChessColor) {
        cancelThinking()
        cancelConfirm()
        startFen = fen
        game = ChessGame(fen: fen)
        self.vsComputer = vsComputer
        playerColor = color
        resetBoardState()
        phase = .playing
        EnergyStore.shared.beginSession()
        save()
        if !checkEnd() { continueComputerIfNeeded() }
    }

    /// コンピュータ戦を、選んだ色で始める。
    func choose(color: ChessColor) {
        SoundManager.shared.playTap()
        ChessStore.lastColor = color
        startGame(fen: ChessPosition.startFen, vsComputer: true, color: color)
    }

    /// 決着のあとの「もういちど」。
    func playAgain() {
        SoundManager.shared.playTap()
        ChessStore.clearSaved(for: mode)
        if mode == .sandbox {
            // 同じ並びからもう一度試せるように、盤を残す
            load(arrangement: startFen)
            resetBoardState()
            vsComputer = false
            playerColor = .white
            phase = .arranging
            saveArrangement()
        } else {
            showFirstPhase()
        }
    }

    // MARK: 盤を読む

    /// 手前に黒を置くか。コンピュータ戦で黒を選んだときだけ。ふたりで指すときは回さない。
    var isFlipped: Bool {
        vsComputer && playerColor == .black && phase != .choosingColor
    }

    /// 盤に見せる駒。
    func piece(at square: Int) -> ChessPiece? {
        phase == .arranging ? arranged[square] : game.position.piece(at: square)
    }

    /// チェックされているキングのマス。無ければ nil。
    var checkedKing: Int? {
        guard phase == .playing || phase == .finished else { return nil }
        let position = game.position
        guard position.inCheck(position.turn) else { return nil }
        let king = position.findKing(position.turn)
        return king >= 0 ? king : nil
    }

    /// 棋譜の文字。交互に指すので、色は手番から順に決まる。
    var recordText: String {
        let start = ChessPosition(fen: startFen)
        var color = start.turn
        let list = sans.map { san -> (san: String, color: ChessColor) in
            defer { color = color.opposite }
            return (san, color)
        }
        return ChessNotation.text(list, firstNumber: Int(start.fullMove))
    }

    var boardPieces: [ChessPiece?] { (0..<64).map(piece(at:)) }

    var boardMarks: ChessBoardMarks {
        var marks = ChessBoardMarks()
        marks.pick = selected
        marks.goto = Set(targets.map(\.to))
        if let lastMove { marks.last = [lastMove.from, lastMove.to] }
        marks.check = checkedKing
        return marks
    }

    var canMove: Bool {
        guard phase == .playing, !isThinking, promotionChoices.isEmpty else { return false }
        return !vsComputer || game.position.turn == playerColor
    }

    // MARK: 指す

    func tap(square: Int) {
        if phase == .arranging {
            place(at: square)
            return
        }
        guard canMove else { return }

        if selected != nil {
            let found = targets.filter { $0.to == square }
            if found.count > 1 {
                // なる駒 4 通り
                promotionChoices = found
                return
            }
            if let move = found.first {
                play(move)
                return
            }
        }

        if selected == square {
            clearSelection()
        } else if let piece = game.position.piece(at: square), piece.color == game.position.turn {
            selected = square
            targets = game.position.moves(from: square)
            SoundManager.shared.playTap()
        } else {
            clearSelection()
        }
    }

    func choosePromotion(_ move: ChessMove) {
        promotionChoices = []
        play(move)
    }

    func cancelPromotion() {
        promotionChoices = []
    }

    private func clearSelection() {
        selected = nil
        targets = []
        promotionChoices = []
    }

    private func play(_ move: ChessMove) {
        cancelConfirm()
        record(move)
        clearSelection()
        save()
        if !checkEnd() { continueComputerIfNeeded() }
    }

    /// 手を盤に乗せて、棋譜に積み、音を鳴らす。
    private func record(_ move: ChessMove) {
        past.append(game)
        sans.append(game.position.san(of: move))
        moves.append(move)
        game.play(move)
        lastMove = move
        SoundManager.shared.playTap()
        if move.isCapture { SoundManager.shared.vibrate() }
    }

    // MARK: 相手

    private func letComputerMove() {
        cancelThinking()
        isThinking = true
        let snapshot = game
        let level = ChessStore.level
        let flag = ChessStopFlag()
        stopFlag = flag
        let started = ContinuousClock.now

        thinkTask = Task { [weak self] in
            let choice = await Task.detached(priority: .userInitiated) {
                ChessAI.choose(in: snapshot, level: level, shouldStop: { flag.isStopped })
            }.value
            // 考えた時間を引いて、どの段でも間を揃える
            let elapsed = ContinuousClock.now - started
            let wait = max(C.computerMinimum, C.computerTotal - elapsed / .seconds(1))
            try? await Task.sleep(for: .seconds(wait))
            guard let self, !flag.isStopped else { return }
            self.isThinking = false
            guard let move = choice?.move else { return }
            self.record(move)
            self.save()
            _ = self.checkEnd()
        }
    }

    private func cancelThinking() {
        stopFlag?.isStopped = true
        stopFlag = nil
        thinkTask?.cancel()
        thinkTask = nil
        isThinking = false
    }

    // MARK: 決着

    private static func ending(from status: ChessStatus) -> Ending? {
        switch status.kind {
        case .checkmate:                return status.winner.map { .checkmate(winner: $0) }
        case .stalemate:                return .stalemate
        case .material:                 return .material
        case .repetition, .repetition5: return .repetition
        case .fifty, .seventyfive:      return .fifty
        case nil:                       return nil
        }
    }

    /// 決着がついていれば終わらせる。主張できるだけの引き分けも決着として扱う（Web 版と同じ）。
    private func checkEnd() -> Bool {
        let status = game.status()
        guard status.over || status.claimable, let end = Self.ending(from: status) else { return false }
        finish(end)
        return true
    }

    private func finish(_ end: Ending) {
        cancelThinking()
        cancelConfirm()
        clearSelection()
        ending = end
        phase = .finished

        if mode == .computer { settle(end) }
        if vsComputer {
            ChessStore.clearSaved(for: mode)
        } else {
            save()
        }
        playEndSound(end)
    }

    /// 段を動かし、勝っていれば報酬を渡す。報酬の額は勝った瞬間の段で決まる。
    private func settle(_ end: Ending) {
        let level = ChessStore.level
        switch end {
        case .checkmate(let winner) where winner == playerColor:
            EnergyStore.shared.grantClearBonus(EnergyRewards.chessWinReward(level: level))
            GameDailyBonus.shared.claim(.chess)
            ChessStore.level = ChessLadder.level(after: .win, from: level)
        case .checkmate:
            ChessStore.level = ChessLadder.level(after: .checkmated, from: level)
        case .resigned:
            ChessStore.level = ChessLadder.level(after: .resigned, from: level)
        case .stalemate, .material, .repetition, .fifty:
            ChessStore.level = ChessLadder.level(after: .draw, from: level)
        }
    }

    private func playEndSound(_ end: Ending) {
        guard vsComputer else {
            SoundManager.shared.playTenClear()
            return
        }
        if case .checkmate(let winner) = end, winner == playerColor {
            SoundManager.shared.playTenClear()
        } else {
            SoundManager.shared.playGameOver()
        }
    }

    /// 自分が勝ったか。
    var didPlayerWin: Bool {
        if case .checkmate(let winner) = ending { return winner == playerColor }
        return false
    }

    // MARK: もどす

    var canUndo: Bool {
        if vsComputer {
            guard phase == .playing else { return false }
            // 相手の手と自分の手を 1 組で戻す。相手の最初の 1 手は戻せない
            return game.position.turn == playerColor ? past.count >= 2 : past.count >= 1
        }
        return (phase == .playing || phase == .finished) && !past.isEmpty
    }

    func undo() {
        guard canUndo else { return }
        SoundManager.shared.playTap()
        cancelThinking()
        cancelConfirm()
        if mode == .computer { ChessStore.level = ChessLadder.levelAfterUndo(from: ChessStore.level) }
        stepBack()
        if vsComputer && game.position.turn != playerColor { stepBack() }
        ending = nil
        phase = .playing
        clearSelection()
        lastMove = moves.last
        save()
    }

    private func stepBack() {
        guard let previous = past.popLast() else { return }
        game = previous
        moves.removeLast()
        sans.removeLast()
    }

    // MARK: 投了・はじめから

    var canResign: Bool { vsComputer && phase == .playing }

    /// 投了。1 回目は確認だけで、もう一度押すと負けになる。
    func resign() {
        guard canResign else { return }
        guard isConfirming else {
            askConfirm()
            return
        }
        finish(.resigned)
    }

    /// ふたりで指しているときの「はじめから」。
    func restartTwoPlayers() {
        guard mode == .twoPlayers else { return }
        if phase == .playing && !moves.isEmpty && !isConfirming {
            askConfirm()
            return
        }
        ChessStore.clearSaved(for: mode)
        SoundManager.shared.playTap()
        showFirstPhase()
    }

    /// 「ならべて」で、対局をやめて並べる画面に戻る。
    func backToArranging() {
        guard mode == .sandbox, phase == .playing else { return }
        if !moves.isEmpty && !isConfirming {
            askConfirm()
            return
        }
        cancelThinking()
        playAgain()
    }

    private func askConfirm() {
        SoundManager.shared.playTap()
        isConfirming = true
        confirmTask?.cancel()
        confirmTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(C.confirmWait))
            guard !Task.isCancelled else { return }
            self?.isConfirming = false
        }
    }

    private func cancelConfirm() {
        confirmTask?.cancel()
        confirmTask = nil
        isConfirming = false
    }

    // MARK: ならべて

    static let palette: [ChessPiece] = [ChessColor.white, .black].flatMap { color in
        [ChessPieceType.king, .queen, .rook, .bishop, .knight, .pawn].map { ChessPiece($0, color) }
    }

    func hold(_ piece: ChessPiece) {
        SoundManager.shared.playTap()
        held = held == piece ? nil : piece
        arrangeNotice = nil
    }

    private func place(at square: Int) {
        if arranged[square] != nil {
            // 置いた駒を押したら取り除く
            arranged[square] = nil
            arrangeNotice = nil
            SoundManager.shared.playTap()
            saveArrangement()
            return
        }
        guard let held else {
            arrangeNotice = "chess_arrange_hint"
            return
        }
        let own = arranged.compactMap { $0 }.filter { $0.color == held.color }
        if held.type == .king && own.contains(where: { $0.type == .king }) {
            arrangeNotice = "chess_err_one_king"
        } else if held.type == .pawn && [1, 8].contains(ChessSquare.rank(square)) {
            arrangeNotice = "chess_err_pawn_row"
        } else if held.type == .pawn && own.filter({ $0.type == .pawn }).count >= 8 {
            arrangeNotice = "chess_err_pawns"
        } else if own.count >= 16 {
            arrangeNotice = "chess_err_pieces"
        } else {
            arranged[square] = held
            arrangeNotice = nil
            SoundManager.shared.playTap()
            saveArrangement()
        }
    }

    func fillStartPosition() {
        SoundManager.shared.playTap()
        load(arrangement: ChessPosition.startFen)
        arrangeNotice = nil
        saveArrangement()
    }

    func clearArrangement() {
        SoundManager.shared.playTap()
        arranged = Array(repeating: nil, count: 64)
        arrangeNotice = nil
        saveArrangement()
    }

    private func load(arrangement fen: String) {
        let position = ChessPosition(fen: fen)
        arranged = (0..<64).map { position.piece(at: $0) }
    }

    /// 並べた盤の FEN。白から指す。キングとルークがはじめの場所にいる組だけキャスリングできる。
    private var arrangedFen: String {
        func has(_ square: Int, _ fen: Character) -> Bool { arranged[square]?.fen == fen }
        var castle = ""
        if has(60, "K") && has(63, "R") { castle += "K" }
        if has(60, "K") && has(56, "R") { castle += "Q" }
        if has(4, "k") && has(7, "r") { castle += "k" }
        if has(4, "k") && has(0, "r") { castle += "q" }
        return "\(ChessPosition.placement { arranged[$0] }) w \(castle.isEmpty ? "-" : castle) - 0 1"
    }

    /// 並べた盤で始める。
    /// - Parameter computerColor: コンピュータと指すときの自分の色。ふたりで指すなら nil
    func startArranged(computerColor: ChessColor?) {
        let fen = arrangedFen
        let position = ChessPosition(fen: fen)
        guard position.findKing(.white) >= 0, position.findKing(.black) >= 0 else {
            arrangeNotice = "chess_err_kings"
            return
        }
        guard !position.inCheck(.black) else {
            arrangeNotice = "chess_err_check"
            return
        }
        SoundManager.shared.playTap()
        arrangeNotice = nil
        held = nil
        startGame(fen: fen, vsComputer: computerColor != nil, color: computerColor ?? .white)
    }

    // MARK: 保存

    private func save() {
        let saved = ChessSavedGame(startFen: startFen, moves: moves.map(\.coordinate),
                                   playerColor: playerColor.fenLetter,
                                   vsComputer: vsComputer, isArranging: false)
        ChessStore.save(saved, for: mode)
    }

    private func saveArrangement() {
        startFen = arrangedFen
        let saved = ChessSavedGame(startFen: startFen, moves: [], playerColor: "w",
                                   vsComputer: false, isArranging: true)
        ChessStore.save(saved, for: mode)
    }
}
