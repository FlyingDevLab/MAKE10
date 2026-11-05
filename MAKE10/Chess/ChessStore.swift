//
//  ChessStore.swift
//  FDL-TenBlitz
//
//  チェスの保存。強さの段・前回の色・前回のモード・途中の対局を UserDefaults に置く。
//
// ★ 途中の対局は「はじめの盤と、指した手の並び」で持つ ★
//   局面だけを保存すると、千日手の回数や「もどす」の履歴が消える。
//   手の並びなら、読み直すときに 1 手ずつ指し直すだけで全部もとどおりになる。
//
// ★ 全部この端末の中だけ ★
//   段は端末で別でも困らない。途中の対局は、2 台で別々に進めたものを合わせられない。
//

import Foundation

/// 途中の対局。1 手ごとに書き直す。
struct ChessSavedGame: Codable {
    var startFen: String
    /// 指した手。'e2e4' の形
    var moves: [String]
    /// 手前に持つ色。"w" か "b"
    var playerColor: String
    var vsComputer: Bool
    /// 「ならべて」で、まだ駒を並べている途中か。そのとき startFen が並べた盤
    var isArranging: Bool
}

enum ChessStore {

    // MARK: 強さの段

    /// いまの段。画面には出さない（ChessLadder.swift を参照）。
    static var level: Int {
        get {
            let saved = UserDefaults.standard.integer(forKey: UDKey.chessLevel)
            return (ChessLadder.minLevel...ChessLadder.maxLevel).contains(saved) ? saved : ChessLadder.startLevel
        }
        set { UserDefaults.standard.set(newValue, forKey: UDKey.chessLevel) }
    }

    // MARK: 前回の選び

    static var lastColor: ChessColor {
        get { ChessColor(fenLetter: UserDefaults.standard.string(forKey: UDKey.chessPlayerColor) ?? "") }
        set { UserDefaults.standard.set(newValue.fenLetter, forKey: UDKey.chessPlayerColor) }
    }

    /// 前回ひらいていた場所。
    static var lastSection: ChessSection {
        get {
            UserDefaults.standard.string(forKey: UDKey.chessLastMode)
                .flatMap(ChessSection.init(rawValue:)) ?? .computer
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: UDKey.chessLastMode) }
    }

    // MARK: 途中の対局

    private static func loadAll() -> [String: ChessSavedGame] {
        guard let text = UserDefaults.standard.string(forKey: UDKey.chessSavedGames),
              let data = text.data(using: .utf8),
              let games = try? JSONDecoder().decode([String: ChessSavedGame].self, from: data) else { return [:] }
        return games
    }

    private static func storeAll(_ games: [String: ChessSavedGame]) {
        guard let data = try? JSONEncoder().encode(games),
              let text = String(data: data, encoding: .utf8) else { return }
        UserDefaults.standard.set(text, forKey: UDKey.chessSavedGames)
    }

    static func saved(for mode: ChessViewModel.Mode) -> ChessSavedGame? {
        loadAll()[mode.rawValue]
    }

    static func save(_ game: ChessSavedGame, for mode: ChessViewModel.Mode) {
        var games = loadAll()
        games[mode.rawValue] = game
        storeAll(games)
    }

    static func clearSaved(for mode: ChessViewModel.Mode) {
        var games = loadAll()
        games[mode.rawValue] = nil
        storeAll(games)
    }

    // MARK: リセット

    /// 「さいしょから はじめる」のときに、段・前回の選び・途中の対局を消す。
    static func reset() {
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: UDKey.chessLevel)
        defaults.removeObject(forKey: UDKey.chessPlayerColor)
        defaults.removeObject(forKey: UDKey.chessLastMode)
        defaults.removeObject(forKey: UDKey.chessSavedGames)
    }
}
