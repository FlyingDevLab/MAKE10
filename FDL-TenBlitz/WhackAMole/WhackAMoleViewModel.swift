//
//  WhackAMoleViewModel.swift
//  FDL-TenBlitz
//
//  Created by 空飛ぶ研究室(FlyingDevLab) on 2026/04/13.
//

// game.js のロジックを Swift に移植したモグラ叩きの状態管理クラス。
// ゲーム開始・終了・タイマー・モグラのスポーン／消滅・スコア・ハイスコアを管理する。
//
// 主な調整ポイント:
//   難易度    → WAMConfig の Phase 定義
//   アニメ速度 → showMole / hideMole / whackMole の withAnimation
//   叩いた演出 → whackMole の isHit リセット遅延（0.35秒）
//
// フェーズ設計（残り時間で自動切り替え）:
//   フェーズ1  残り27〜30秒  目標  6点  spawn 0.50〜0.85秒  maxSim 2
//   フェーズ2  残り22〜26秒  目標 12点  spawn 0.30〜0.54秒  maxSim 3
//   フェーズ3  残り17〜21秒  目標 18点  spawn 0.20〜0.36秒  maxSim 4
//   フェーズ4  残り11〜16秒  目標 24点  spawn 0.18〜0.32秒  maxSim 5
//   フェーズ5  残り 0〜10秒  目標 48点  spawn 0.15〜0.27秒  maxSim 7
//   理論最高スコア: 108点（100点は射程内）

import SwiftUI

// MARK: - WAMConfig（ゲームパラメータ設定）
// Phase 定義を変えるだけで難易度・テンポを調整できる

private enum WAMConfig {

    // ── タイマー ──────────────────────────────────────────────
    /// ゲームの制限時間（秒）
    static let gameDuration      = 30

    // ── グリッド ──────────────────────────────────────────────
    /// 穴の総数。3×3 = 9 固定（変えるときは View の columns も合わせて変更）
    static let holeCount         = 9

    // ── 警告しきい値 ──────────────────────────────────────────
    /// 残り時間がこの値以下になるとタイマーが警告色に変わる（秒）
    static let warningThreshold  = 10

    // ── フェーズ定義 ──────────────────────────────────────────
    // 残り時間に応じて自動的にフェーズが切り替わる。
    // 各フェーズのパラメータを変えるだけで難易度全体を調整できる。

    struct Phase {
        /// 同時に出ているモグラの上限数
        let maxSimultaneous:  Int
        /// 次のモグラが出るまでの最短待ち時間（秒）
        let spawnIntervalMin: Double
        /// 次のモグラが出るまでの最長待ち時間（秒）
        let spawnIntervalMax: Double
        /// モグラが穴から出ている最短時間（秒）
        let moleUpMin:        Double
        /// モグラが穴から出ている最長時間（秒）
        let moleUpMax:        Double
    }

    // フェーズ1: ウォームアップ（残り27〜30秒 ≈ 4秒間）
    // spawn平均 0.675秒 × 4秒 ≒ 6点
    static let phase1 = Phase(
        maxSimultaneous:  2,
        spawnIntervalMin: 0.50,
        spawnIntervalMax: 0.85,
        moleUpMin:        1.5,
        moleUpMax:        2.0
    )

    // フェーズ2: テンポアップ（残り22〜26秒 ≈ 5秒間）
    // spawn平均 0.42秒 × 5秒 ≒ 12点
    static let phase2 = Phase(
        maxSimultaneous:  3,
        spawnIntervalMin: 0.30,
        spawnIntervalMax: 0.54,
        moleUpMin:        1.2,
        moleUpMax:        1.8
    )

    // フェーズ3: 中盤加速（残り17〜21秒 ≈ 5秒間）
    // spawn平均 0.28秒 × 5秒 ≒ 18点
    static let phase3 = Phase(
        maxSimultaneous:  4,
        spawnIntervalMin: 0.20,
        spawnIntervalMax: 0.36,
        moleUpMin:        1.0,
        moleUpMax:        1.5
    )

    // フェーズ4: 後半ラッシュ（残り11〜16秒 ≈ 6秒間）
    // spawn平均 0.25秒 × 6秒 ≒ 24点
    static let phase4 = Phase(
        maxSimultaneous:  5,
        spawnIntervalMin: 0.18,
        spawnIntervalMax: 0.32,
        moleUpMin:        0.8,
        moleUpMax:        1.3
    )

    // フェーズ5: 怒濤のラストスパート（残り0〜10秒 ≈ 10秒間）
    // spawn平均 0.21秒 × 10秒 ≒ 48点
    static let phase5 = Phase(
        maxSimultaneous:  7,
        spawnIntervalMin: 0.15,
        spawnIntervalMax: 0.27,
        moleUpMin:        0.6,
        moleUpMax:        1.0
    )
}

// MARK: - MoleState（穴1つのモグラ状態）

/// 各穴のモグラの表示状態。View への binding に使う。
struct MoleState {
    /// 穴からモグラが出ているか（true = 叩ける）
    var isVisible: Bool = false
    /// 叩かれた直後のアニメーション中か（true = ⭐演出を表示）
    var isHit:     Bool = false
}

// MARK: - WhackAMoleViewModel

@Observable
final class WhackAMoleViewModel {

    // MARK: - ゲーム状態

    enum GameState { case title, playing, finished }

    var gameState:   GameState = .title
    var score:       Int       = 0
    var timeLeft:    Int       = WAMConfig.gameDuration
    var isNewRecord: Bool      = false

    /// 各穴のモグラ状態（インデックス 0〜8: 左上→右下の順）
    var moles: [MoleState] = Array(repeating: MoleState(), count: WAMConfig.holeCount)

    /// UserDefaults から読み込んだハイスコア（常に最新値を返す）
    var highScore: Int {
        UserDefaults.standard.integer(forKey: UDKey.whackHighScore)
    }

    /// 残り時間が warningThreshold 以下なら true（タイマーの色変化に使う）
    var isTimerWarning: Bool { timeLeft <= WAMConfig.warningThreshold }

    // MARK: - 内部状態

    private var countdownTimer: Timer?         // 1秒ごとに timeLeft を減らすタイマー
    private var spawnTask: DispatchWorkItem?   // 次のモグラを出すスケジュールタスク

    /// 各穴の自動消滅タスク（index = 穴番号）。叩いたときにキャンセルする。
    private var moleHideTasks: [DispatchWorkItem?] = Array(
        repeating: nil, count: WAMConfig.holeCount
    )

    /// 現在モグラが出ている穴のインデックスセット（同時出現数の制御に使う）
    private var activeMoles: Set<Int> = []

    // MARK: - フェーズ管理

    /// 残り時間に応じて現在のフェーズパラメータを返す。
    /// timeLeft が減るたびに自動的に次フェーズへ移行する。
    private var currentPhase: WAMConfig.Phase {
        switch timeLeft {
        case 27...: return WAMConfig.phase1   // 残り27秒以上：ウォームアップ
        case 22...: return WAMConfig.phase2   // 残り22〜26秒：テンポアップ
        case 17...: return WAMConfig.phase3   // 残り17〜21秒：中盤加速
        case 11...: return WAMConfig.phase4   // 残り11〜16秒：後半ラッシュ
        default:    return WAMConfig.phase5   // 残り10秒以下：怒濤のラストスパート
        }
    }

    // MARK: - 外部公開メソッド

    func startGame() {
        resetState()
        gameState = .playing
        startCountdown()
        scheduleNextSpawn()
    }

    /// バックボタン・onDisappear から呼ばれる強制停止
    /// タイマーとスポーンタスクをすべてキャンセルしモグラを全非表示にする
    func stopGame() {
        countdownTimer?.invalidate()
        countdownTimer = nil
        spawnTask?.cancel()
        spawnTask = nil
        cancelAllMoleTasks()
        hideAllMoles()
    }

    // MARK: - リセット

    private func resetState() {
        score       = 0
        timeLeft    = WAMConfig.gameDuration
        isNewRecord = false
        activeMoles.removeAll()
        moles         = Array(repeating: MoleState(), count: WAMConfig.holeCount)
        moleHideTasks = Array(repeating: nil,         count: WAMConfig.holeCount)
    }

    // MARK: - カウントダウンタイマー

    private func startCountdown() {
        // 1秒ごとに timeLeft を 1 減らし、0 になったらゲーム終了する
        countdownTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.timeLeft -= 1
            if self.timeLeft <= 0 {
                self.endGame()
            }
        }
    }

    // MARK: - モグラスポーン

    /// 現在フェーズのspawn間隔でtrySpawnMoleを繰り返し呼び出す再帰スケジューラ。
    /// scheduleNextSpawn が呼ばれるたびに currentPhase を参照するため、
    /// フェーズ移行はタイマーに依存せず自動的に反映される。
    private func scheduleNextSpawn() {
        guard gameState == .playing else { return }
        let phase = currentPhase
        let delay = Double.random(in: phase.spawnIntervalMin...phase.spawnIntervalMax)
        let task  = DispatchWorkItem { [weak self] in
            guard let self, self.gameState == .playing else { return }
            self.trySpawnMole()
            self.scheduleNextSpawn()  // 再帰: 次のスポーンを予約
        }
        spawnTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: task)
    }

    /// 空き穴にランダムでモグラを出す（現在フェーズの同時出現数上限チェックあり）
    private func trySpawnMole() {
        guard activeMoles.count < currentPhase.maxSimultaneous else { return }
        let empty = (0..<WAMConfig.holeCount).filter { !activeMoles.contains($0) }
        guard let index = empty.randomElement() else { return }
        showMole(at: index)
    }

    /// 指定インデックスの穴からモグラを出現させ、現在フェーズのmoleUpTime後に自動で引っ込める
    private func showMole(at index: Int) {
        activeMoles.insert(index)

        withAnimation(.spring(duration: 0.25)) {
            moles[index].isVisible = true
            moles[index].isHit     = false
        }

        // 現在フェーズの滞在時間でタイマーをセット
        let phase    = currentPhase
        let duration = Double.random(in: phase.moleUpMin...phase.moleUpMax)
        let task = DispatchWorkItem { [weak self] in
            self?.hideMole(at: index, missed: true)
        }
        moleHideTasks[index] = task
        DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: task)
    }

    /// 指定インデックスのモグラを穴に引っ込める
    private func hideMole(at index: Int, missed: Bool) {
        guard moles[index].isVisible else { return }

        withAnimation(.easeIn(duration: 0.2)) {
            moles[index].isVisible = false
            moles[index].isHit     = false
        }
        activeMoles.remove(index)
        moleHideTasks[index]?.cancel()
        moleHideTasks[index] = nil
    }

    private func hideAllMoles() {
        for i in 0..<WAMConfig.holeCount {
            moles[i].isVisible = false
            moles[i].isHit     = false
        }
        activeMoles.removeAll()
    }

    private func cancelAllMoleTasks() {
        moleHideTasks.forEach { $0?.cancel() }
        moleHideTasks = Array(repeating: nil, count: WAMConfig.holeCount)
    }

    // MARK: - ヒット処理

    /// 指定インデックスのモグラを叩く（View の onTapGesture から呼ばれる）
    func whackMole(at index: Int) {
        guard gameState == .playing, activeMoles.contains(index) else { return }

        // 自動消滅タスクをキャンセル（叩いたので自動消滅は不要）
        moleHideTasks[index]?.cancel()
        moleHideTasks[index] = nil
        activeMoles.remove(index)

        // isHit = true にすると View で ⭐ が表示される
        withAnimation(.spring(duration: 0.12)) {
            moles[index].isVisible = false
            moles[index].isHit     = true
        }
        // 0.35秒後に isHit をリセット（⭐ 表示時間）
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            self?.moles[index].isHit = false
        }

        score += 1
        SoundManager.shared.vibrate()
        SoundManager.shared.playTap()
    }

    // MARK: - ゲーム終了

    private func endGame() {
        stopGame()
        isNewRecord = checkAndSaveHighScore(score)
        withAnimation(.easeInOut(duration: 0.3)) {
            gameState = .finished
        }
    }

    // MARK: - ハイスコア管理

    /// 現在スコアがハイスコアを超えていれば UserDefaults に保存し true を返す
    private func checkAndSaveHighScore(_ current: Int) -> Bool {
        let prev = UserDefaults.standard.integer(forKey: UDKey.whackHighScore)
        guard current > prev else { return false }
        UserDefaults.standard.set(current, forKey: UDKey.whackHighScore)
        return true
    }
}
