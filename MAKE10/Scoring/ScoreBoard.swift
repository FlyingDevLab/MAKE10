//
//  ScoreBoard.swift
//  FDL-TenBlitz
//
//  Created by 空飛ぶ研究室(FlyingDevLab) on 2026/06/09.
//

// 全ゲームのスコア・ベストタイムに関する UserDefaults 操作を一元管理するユーティリティ。
//
// 役割分担:
//   - UDKey (MakeTenModels.swift) : キー文字列の定義（タイポ防止のための一元管理）
//   - ScoreBoard（このファイル）   : スコアの読み書き・新記録判定・リセットのロジック
//   - 各ゲームの ViewModel        : ゲーム終了時に ScoreBoard.saveIfBetter() 等を呼ぶだけ
//
// ★ このファイルの役割 ★
//   各ゲームのスコア読み書きとリセットをここに集約することで、
//   「新ゲームを追加するときは ScoreBoard にキーを追加するだけ」
//   という状態を維持します。
//
// ★ なぜ enum にするのか ★
//   インスタンスを作る必要がない純粋なユーティリティのため、
//   case を持たない enum にすることで誤って初期化されることを防ぎます。
//   ScoreBoard() と書けないため、必ず ScoreBoard.xxx の形で使います。
//
// ★ iCloud との同期 ★（CloudSyncManager.swift を参照）
//   全ゲームのスコア・ベストタイムを1つの記録（"scores"）にする。係は下の ScoreBoardSync。
//   2台で食い違ったら、キーごとに「よいほう」を残す（スコアは大きいほう、ベストタイムは速いほう）。
//   どちらの端末の記録も損をしないので、ほかの記録のような「あとで変えたほう」にはしない。

import Foundation

// MARK: - ScoreBoard

enum ScoreBoard {

    // MARK: 全スコアキー一覧
    //
    // ★ ここが設計の核心 ★
    //   全ゲームのスコア・ベストタイムに使う UDKey をここに集約します。
    //   新ゲームを追加したときは、このリストにキーを追加するだけで
    //   resetAll() が自動的にそのスコアもリセット対象に含めます。
    //   追加し忘れてもコンパイルエラーにはなりませんが、
    //   一覧性があるためレビューで気づきやすくなります。

    static let allScoreKeys: [String] = [
        // ── MAKE10 ────────────────────────────────
        UDKey.normalHighScore,
        UDKey.blitzHighScore,
        // ── WhackAMole ────────────────────────────
        UDKey.whackHighScore,
        // ── MazeGame ──────────────────────────────
        UDKey.mazeHighScore,
        // ── Pinball ───────────────────────────────
        UDKey.pinballHighScore,
        // ── CoinDrop ──────────────────────────────
        UDKey.coinDropHighScore,
        // ── Janken ────────────────────────────────
        UDKey.jankenBestTimeEasy,
        UDKey.jankenBestTimeHard,
        UDKey.jankenBestTimeChallenge,
    ]

    // MARK: Int 型スコア（Pinball / CoinDrop / Maze / Blitz）

    /// 指定キーの最高スコアを返す。未記録の場合は 0。
    static func highScore(for key: String) -> Int {
        UserDefaults.standard.integer(forKey: key)
    }

    /// currentが過去最高を上回っていれば保存して true を返す。
    /// 更新がなければ UserDefaults への書き込みは行わない。
    ///
    /// ★ @discardableResult とは？ ★
    ///   戻り値を使わなくてもコンパイル警告が出ないようにするマークです。
    ///   「新記録かどうか」を画面表示に使いたい場合は戻り値を受け取り、
    ///   使わない場合は無視できます。
    @discardableResult
    static func saveIfBetter(score current: Int, for key: String) -> Bool {
        let prev = UserDefaults.standard.integer(forKey: key)
        guard current > prev else { return false }
        UserDefaults.standard.set(current, forKey: key)
        ScoreBoardSync.shared.markChanged()
        return true
    }

    // MARK: TimeInterval 型ベストタイム（Janken）

    /// 指定キーのベストタイムを返す。未記録の場合は nil。
    ///
    /// ★ なぜ 0 を nil に変換するのか ★
    ///   UserDefaults に未記録のキーを double(forKey:) で読むと 0.0 が返ります。
    ///   0 秒という記録は存在しないため、0 は「記録なし」として nil を返します。
    static func bestTime(for key: String) -> TimeInterval? {
        let v = UserDefaults.standard.double(forKey: key)
        return v > 0 ? v : nil
    }

    /// currentが過去最速（または未記録）であれば保存して true を返す。
    /// 更新がなければ UserDefaults への書き込みは行わない。
    @discardableResult
    static func saveIfFaster(time current: TimeInterval, for key: String) -> Bool {
        let prev = UserDefaults.standard.double(forKey: key)
        guard current < prev || prev == 0 else { return false }
        UserDefaults.standard.set(current, forKey: key)
        ScoreBoardSync.shared.markChanged()
        return true
    }

    /// ベストタイム（速いほどよい記録）のキー。iCloud で合わせるときに「小さいほう」を残すために使う。
    static let timeKeys: Set<String> = [
        UDKey.jankenBestTimeEasy,
        UDKey.jankenBestTimeHard,
        UDKey.jankenBestTimeChallenge,
    ]

    // MARK: リセット

    /// 全ゲームのスコア・ベストタイムを削除する。
    /// GameViewModel.resetProgress() から呼ばれ、アプリの進捗を初期化する。
    ///
    /// ★ removeObject と set(0) の違い ★
    ///   set(0) は「0という値を保存」するのに対し、
    ///   removeObject は「キー自体を削除」します。
    ///   削除しておくと highScore(for:) が 0 を返し、
    ///   bestTime(for:) が nil を返すため、
    ///   各ゲームが「未記録」状態として正しく振る舞います。
    static func resetAll() {
        allScoreKeys.forEach {
            UserDefaults.standard.removeObject(forKey: $0)
        }
    }
}

// MARK: - ScoreBoardSync（iCloud との同期の係）

/// ScoreBoard の記録を iCloud とやりとりする係。
/// ★ ScoreBoard とは別に作っている理由 ★
///   iCloud の約束（CloudSyncSource）は「物」（クラスのインスタンス）が守る約束なので、
///   インスタンスを作らない enum の ScoreBoard には付けられない。そこで小さな係を1つだけ作っている。
final class ScoreBoardSync: CloudSyncSource {

    static let shared = ScoreBoardSync()
    private static let recordName = "scores"

    private init() {}

    /// 記録が変わったことを iCloud の係に知らせる（iCloud を使っていなければ何も起きない）。
    func markChanged() {
        CloudSyncManager.shared.markChanged(Self.recordName)
    }

    var cloudRecordNames: [String] { [Self.recordName] }

    /// 全キーの記録を [キー: 値] にして送る（記録のないキーは入れない）。
    func cloudPayload(for name: String) -> CloudPayload? {
        guard let data = try? JSONEncoder().encode(localScores()) else { return nil }
        // キーごとに「よいほう」で合わせるので、時刻は使わない（.distantPast でよい）
        return CloudPayload(data: data, modifiedAt: .distantPast)
    }

    /// iCloud から届いた記録を、キーごとに「よいほう」で合わせる。
    func applyCloudPayload(_ payload: CloudPayload, for name: String, force: Bool) -> CloudApplyResult {
        guard let remote = try? JSONDecoder().decode([String: Double].self, from: payload.data) else { return .applied }
        let defaults = UserDefaults.standard
        var merged   = force ? [:] : localScores()

        for key in ScoreBoard.allScoreKeys {
            guard let remoteValue = remote[key], remoteValue > 0 else { continue }
            if let localValue = merged[key] {
                merged[key] = ScoreBoard.timeKeys.contains(key) ? min(localValue, remoteValue)   // タイムは速いほう
                                                                : max(localValue, remoteValue)   // スコアは大きいほう
            } else {
                merged[key] = remoteValue
            }
        }
        if force {
            // 「iCloud の記録を もどす」を選んだ → iCloud にない記録は消す
            for key in ScoreBoard.allScoreKeys where merged[key] == nil { defaults.removeObject(forKey: key) }
        }
        for (key, value) in merged {
            if ScoreBoard.timeKeys.contains(key) {
                defaults.set(value, forKey: key)        // ベストタイムは Double（秒）
            } else {
                defaults.set(Int(value), forKey: key)   // スコアは Int
            }
        }
        // 合わせた結果が iCloud と違えば（この端末のほうがよい記録を持っていれば）送り直す
        return merged == remote ? .applied : .keptLocal
    }

    /// どれか1つでも記録があれば「遊んだ」とみなす。
    var hasLocalProgress: Bool { !localScores().isEmpty }

    /// この端末の記録（記録のないキーは入れない）。スコアもタイムも Double にそろえる。
    private func localScores() -> [String: Double] {
        var scores: [String: Double] = [:]
        for key in ScoreBoard.allScoreKeys {
            let value = UserDefaults.standard.double(forKey: key)   // Int で保存した値も Double で読める
            if value > 0 { scores[key] = value }
        }
        return scores
    }
}
