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

    /// 歴代最高スコア。ScoreBoard 経由で読み取る。
    var highScore: Int { ScoreBoard.highScore(for: UDKey.pinballHighScore) }

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
        // 新記録なら ScoreBoard が保存し true を返す。結果画面の表示に使う
        isNewRecord = ScoreBoard.saveIfBetter(score: score, for: UDKey.pinballHighScore)
        withAnimation(.easeInOut(duration: 0.3)) {
            gameState = .finished
        }
    }
}
