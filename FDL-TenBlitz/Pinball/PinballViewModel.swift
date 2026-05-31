//
//  PinballViewModel.swift
//  FDL-TenBlitz
//
//  Created by 空飛ぶ研究室(FlyingDevLab) on 2026/04/13.
//

// ピンボールのアプリレベル状態（スコア・残機・画面遷移）を管理する。
// 実際の物理シミュレーションは PinballScene が担い、
// スコア変化・ボール消失のイベントをコールバックで受け取る。

import SwiftUI

// MARK: - PinballViewModel

@Observable
final class PinballViewModel {

    enum GameState { case title, playing, finished }

    var gameState:   GameState = .title
    var score:       Int       = 0
    var ballsLeft:   Int       = 3
    var isNewRecord: Bool      = false

    var highScore: Int {
        UserDefaults.standard.integer(forKey: UDKey.pinballHighScore)
    }

    // MARK: - Game Control

    func startGame() {
        score       = 0
        ballsLeft   = 3
        isNewRecord = false
        gameState   = .playing
    }

    /// PinballScene からスコア変化を受け取るコールバック
    func updateScore(_ newScore: Int) {
        score = newScore
    }

    /// PinballScene からボール消失を受け取るコールバック
    func ballDrained() {
        ballsLeft -= 1
        if ballsLeft <= 0 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
                self.endGame()
            }
        }
    }

    func returnToTitle() {
        gameState = .title
    }

    // MARK: - Private

    private func endGame() {
        isNewRecord = checkAndSaveHighScore(score)
        withAnimation(.easeInOut(duration: 0.3)) {
            gameState = .finished
        }
    }

    private func checkAndSaveHighScore(_ current: Int) -> Bool {
        let prev = UserDefaults.standard.integer(forKey: UDKey.pinballHighScore)
        guard current > prev else { return false }
        UserDefaults.standard.set(current, forKey: UDKey.pinballHighScore)
        return true
    }
}
