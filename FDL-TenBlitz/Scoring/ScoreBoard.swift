//
//  ScoreBoard.swift
//  FDL-TenBlitz
//
//  Created by 空飛ぶ研究室(FlyingDevLab) on 2026/06/09.
//

// 全ゲームのスコア・ベストタイムに関する UserDefaults 操作を一元管理するユーティリティ。
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
        return true
    }

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
