//
//  PuzzleProgress.swift
//  FDL-TenBlitz
//
//  Created by 空飛ぶ研究室(FlyingDevLab) on 2026/11/04.
//

// かわわたり → クロツキ → 華容道 → 箱入り娘 → CHESS と続く「順番に解放する」道のりの記録。
//
// ★ 解放の順番 ★
//   10びょうモードの記録ができる（スコア1以上） → かわわたり 1問目
//   1問目 → 2問目 → 3問目 → 4問目 → クロツキ → 華容道 → 箱入り娘（標準） → 箱入り娘（むずかしい） → CHESS
//   手数は問わない。最短でなくても、クリアすれば次が開く。
//
// ★ 記録（ScoreBoard）とは別に持っている理由 ★
//   最少手数を見て「解いたことがある」と判断すると、設定の「ハイスコアをリセット」で
//   解放が閉じ、初回クリア報酬をもう一度もらえてしまう。解放状態はリセットで消さない約束なので、
//   ここに別に持つ（消えるのは「さいしょから はじめる」のときだけ）。
//
// ★ アップデートで最初から遊べるようにするには ★
//   initiallyOpenThrough を変えるだけ。たとえば .klotski にすると、
//   クロツキまでが最初から開く。初回クリア報酬はクリアしたときに渡すので、開いたまま遊んでももらえる。
//
// ★ 数字ではなく名前の集まりで持っている理由 ★
//   「何段目まで進んだか」を数字で持つと、将来ゲームを途中に足したときに、保存した数字の意味がずれる。

import SwiftUI

// MARK: - PuzzleStep

/// 道のりの1段。並び順がそのまま解放の順番。
/// rawValue は保存に使うので変えないこと。
enum PuzzleStep: String, CaseIterable {
    case river1, river2, river3, river4
    case klotski
    case huarongdao
    case hakoiri
    case hakoiriHard
    case chess

    /// この段をクリアすると開く段
    var opens: [PuzzleStep] {
        switch self {
        case .river1:      return [.river2]
        case .river2:      return [.river3]
        case .river3:      return [.river4]
        case .river4:      return [.klotski]
        case .klotski:     return [.huarongdao]
        case .huarongdao:  return [.hakoiri]
        case .hakoiri:     return [.hakoiriHard]
        case .hakoiriHard: return [.chess]
        case .chess:       return []
        }
    }

    /// 初回クリア報酬（kcal）
    var firstClearReward: Double {
        switch self {
        case .river1: return EnergyRewards.firstClearRiver1
        case .river2: return EnergyRewards.firstClearRiver2
        case .river3: return EnergyRewards.firstClearRiver3
        case .river4: return EnergyRewards.firstClearRiver4
        case .klotski, .huarongdao, .hakoiri, .hakoiriHard: return EnergyRewards.firstClearSlidingPuzzle
        case .chess:  return 0
        }
    }

    /// この段が開いたときにタイトル画面へ出るタイル（ステージやモードが開くだけなら nil）
    var tile: GamePickerSelection? {
        switch self {
        case .river1:     return .riverCrossing
        case .klotski:    return .klotski
        case .huarongdao: return .huarongdao
        case .hakoiri:    return .hakoiri
        case .chess:      return .chess
        default:          return nil
        }
    }

    /// 「○○が ひらいた！」に入れる名前
    var openedName: String {
        switch self {
        case .river1:      return String(localized: "river_title")
        case .river2:      return String(localized: "river_stage_weight")
        case .river3:      return String(localized: "river_stage_pairs")
        case .river4:      return String(localized: "river_stage_raft")
        case .klotski:     return String(localized: "klotski_title")
        case .huarongdao:  return String(localized: "huarongdao_title")
        case .hakoiri:     return String(localized: "hakoiri_title")
        case .hakoiriHard: return String(localized: "puzzle_name_hakoiri_hard")
        case .chess:       return String(localized: "chess_title")
        }
    }
}

// MARK: - PuzzleProgress

// @Observable / シングルトンの解説は AppSettings.swift 冒頭を参照
@Observable
final class PuzzleProgress: CloudSyncSource {

    static let shared = PuzzleProgress()

    /// ここまでの段は、最初から遊べる。nil なら10びょうモードの記録ができるまで何も開かない。
    /// アップデートで開放範囲を広げるときは、ここを変えるだけでよい（このファイル冒頭を参照）。
    static let initiallyOpenThrough: PuzzleStep? = nil   // ← 変更可

    /// 解放した段（rawValue）
    private var unlocked: Set<String>
    /// 初回クリア報酬を渡した段（rawValue）
    private var firstCleared: Set<String>
    /// 開いたばかりで、タイトル画面の前へ出すタイル（rawValue）
    private var tilesToBringForward: [String]

    private init() {
        let defaults = UserDefaults.standard
        unlocked            = Set(defaults.stringArray(forKey: UDKey.puzzleUnlocked) ?? [])
        firstCleared        = Set(defaults.stringArray(forKey: UDKey.puzzleFirstCleared) ?? [])
        tilesToBringForward = defaults.stringArray(forKey: UDKey.puzzleTilesToBringForward) ?? []
    }

    // MARK: 判断

    func isUnlocked(_ step: PuzzleStep) -> Bool {
        // 撮影モードでは全部のゲームを開けるようにする（App Store の画像を撮るため）
        if ScreenshotMode.isActive { return true }
        if unlocked.contains(step.rawValue) { return true }
        guard let open = Self.initiallyOpenThrough,
              let openIndex = PuzzleStep.allCases.firstIndex(of: open),
              let index = PuzzleStep.allCases.firstIndex(of: step) else { return false }
        return index <= openIndex
    }

    /// タイトル画面にこのゲームのタイルを出すか。解放の道のりに無いゲームはいつも true。
    func isTileVisible(_ game: GamePickerSelection) -> Bool {
        guard let step = PuzzleStep.allCases.first(where: { $0.tile == game }) else { return true }
        return isUnlocked(step)
    }

    // MARK: 解放

    /// 10びょうモードの記録があれば、かわわたりを開く。
    /// タイトル画面を出すたびに呼ぶ（前の版からの記録や、iCloud から届いた記録でも開くように）。
    /// init で呼ばないのは、ここから iCloud の係（CloudSyncManager）に触るため。
    /// iCloud の係は起動時にこの係を登録するので、init の中で触ると、お互いの初期化を待ち合ってしまう。
    func refreshBlitzRecord() {
        if ScoreBoard.highScore(for: UDKey.blitzHighScore) > 0 { unlock(.river1) }
    }

    /// 段を開く。
    /// - Returns: 今回はじめて開いたら true（「ひらいた！」の表示に使う）
    @discardableResult
    func unlock(_ step: PuzzleStep) -> Bool {
        guard unlocked.insert(step.rawValue).inserted else { return false }
        // 最初から開いている段は、遊んでいるタイルが急に前へ動かないように何もしない
        let isNews = !isOpenFromTheStart(step)
        if isNews, let tile = step.tile { tilesToBringForward.append(tile.rawValue) }
        save()
        return isNews
    }

    /// 最初から開いている段か（開いても「ひらいた！」とは言わない）
    private func isOpenFromTheStart(_ step: PuzzleStep) -> Bool {
        guard let open = Self.initiallyOpenThrough,
              let openIndex = PuzzleStep.allCases.firstIndex(of: open),
              let index = PuzzleStep.allCases.firstIndex(of: step) else { return false }
        return index <= openIndex
    }

    /// クリアしたときの結果。
    struct ClearResult {
        /// 初回クリア報酬（kcal）。2回目以降は 0
        let firstClearReward: Double
        /// 今回あたらしく開いた段（画面に知らせる）
        let opened: [PuzzleStep]
    }

    /// 段をクリアした。次の段を開き、はじめてのクリアなら報酬の額を返す（渡すのは呼び出し側）。
    func clear(_ step: PuzzleStep) -> ClearResult {
        let isFirst = firstCleared.insert(step.rawValue).inserted
        let opened = step.opens.filter { unlock($0) }
        save()
        return ClearResult(firstClearReward: isFirst ? step.firstClearReward : 0, opened: opened)
    }

    /// 開いたばかりのタイルを受け取る（タイトル画面が前へ出す）。受け取ったら空になる。
    func takeTilesToBringForward() -> [GamePickerSelection] {
        let tiles = tilesToBringForward.compactMap(GamePickerSelection.init(rawValue:))
        guard !tilesToBringForward.isEmpty else { return [] }
        tilesToBringForward = []
        UserDefaults.standard.removeObject(forKey: UDKey.puzzleTilesToBringForward)
        return tiles
    }

    // MARK: 保存

    private func save() {
        let defaults = UserDefaults.standard
        defaults.set(unlocked.sorted(), forKey: UDKey.puzzleUnlocked)
        defaults.set(firstCleared.sorted(), forKey: UDKey.puzzleFirstCleared)
        defaults.set(tilesToBringForward, forKey: UDKey.puzzleTilesToBringForward)
        CloudSyncManager.shared.markChanged(Self.recordName)
    }

    /// 「さいしょから はじめる」のときに、解放と初回クリアの記録を消す。
    /// 「ハイスコアをリセット」では呼ばない（このファイル冒頭を参照）。
    func reset() {
        unlocked            = []
        firstCleared        = []
        tilesToBringForward = []
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: UDKey.puzzleUnlocked)
        defaults.removeObject(forKey: UDKey.puzzleFirstCleared)
        defaults.removeObject(forKey: UDKey.puzzleTilesToBringForward)
    }

    // MARK: iCloud（CloudSyncManager.swift を参照）

    private static let recordName = "puzzles"

    /// iCloud に送る中身。
    private struct CloudPuzzles: Codable, Equatable {
        var unlocked:     [String]
        var firstCleared: [String]
    }

    private var local: CloudPuzzles {
        CloudPuzzles(unlocked: unlocked.sorted(), firstCleared: firstCleared.sorted())
    }

    var cloudRecordNames: [String] { [Self.recordName] }

    func cloudPayload(for name: String) -> CloudPayload? {
        guard let data = try? JSONEncoder().encode(local) else { return nil }
        // 足し合わせ方で合わせるので、時刻は使わない（.distantPast でよい）
        return CloudPayload(data: data, modifiedAt: .distantPast)
    }

    /// iCloud から届いた記録を合わせる。
    /// どちらかの端末で開いた・受け取ったものは、両方で開いた・受け取ったことにする。
    /// 開いたものは閉じないし、初回クリア報酬を2回渡さないため。
    func applyCloudPayload(_ payload: CloudPayload, for name: String, force: Bool) -> CloudApplyResult {
        guard let remote = try? JSONDecoder().decode(CloudPuzzles.self, from: payload.data) else { return .applied }
        let mergedUnlocked = force ? Set(remote.unlocked) : unlocked.union(remote.unlocked)

        // 別の端末で開いたタイルも、この端末で隠れた位置に残らないように前へ出す
        let newTiles = mergedUnlocked.subtracting(unlocked)
            .compactMap { PuzzleStep(rawValue: $0)?.tile?.rawValue }
        tilesToBringForward += newTiles

        unlocked     = mergedUnlocked
        firstCleared = force ? Set(remote.firstCleared) : firstCleared.union(remote.firstCleared)
        let defaults = UserDefaults.standard
        defaults.set(unlocked.sorted(), forKey: UDKey.puzzleUnlocked)
        defaults.set(firstCleared.sorted(), forKey: UDKey.puzzleFirstCleared)
        defaults.set(tilesToBringForward, forKey: UDKey.puzzleTilesToBringForward)
        return local == remote ? .applied : .keptLocal
    }

    var hasLocalProgress: Bool { !unlocked.isEmpty || !firstCleared.isEmpty }
}
