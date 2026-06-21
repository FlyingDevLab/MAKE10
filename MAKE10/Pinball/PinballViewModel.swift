//
//  PinballViewModel.swift
//  FDL-TenBlitz
//
//  Created by 空飛ぶ研究室(FlyingDevLab) on 2026/04/13.
//
//  ① 一言サマリ
//  ピンボールのアプリレベル状態（スコア・残機・画面遷移）を管理する ViewModel。
//  実際の物理シミュレーションは PinballScene が担い、スコア変化・ボール消失の
//  イベントをコールバックで受け取って、ここで残機やゲーム終了を判断する。
//
//  ② 役割分担
//    - ViewModel（このファイル）: スコア・残機・画面状態の保持、終了判定、ハイスコア更新
//    - Scene (PinballScene)     : 物理シミュレーション（衝突・得点発生・ボール落下）
//    - View (PinballView)       : 状態に応じた画面切り替えと SpriteScene の生成
//  Scene → ViewModel への通知は onScoreChanged / onBallDrained のコールバックで行う。
//
//  ★ @Observable の解説は AppSettings.swift 冒頭を参照 ★

import SwiftUI

// MARK: - PinballViewModel

/// ピンボールの状態を保持するクラス。View はこのプロパティを見て描画する。
@Observable
final class PinballViewModel {

    /// 画面の状態（タイトル / プレイ中 / 終了）
    enum GameState { case title, playing, finished }

    /// 現在の画面状態
    var gameState:   GameState = .title
    /// 現在スコア（Scene から逐次更新される）
    var score:       Int       = 0
    /// 残り球数（0 でゲームオーバー）
    var ballsLeft:   Int       = 3
    /// 今回のプレイで自己ベストを更新したか
    var isNewRecord: Bool      = false

    /// 歴代最高スコア。ScoreBoard 経由で読み取る。
    var highScore: Int { ScoreBoard.highScore(for: UDKey.pinballHighScore) }

    // MARK: - ゲーム進行

    /// ゲームを最初から開始する（スコア・残機リセット → プレイ状態へ）
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
            // 最後の球が落ちたら、少し余韻を置いてから終了処理へ
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
                self.endGame()
            }
        }
    }

    /// タイトル画面へ戻る
    func returnToTitle() {
        gameState = .title
    }

    // MARK: - 非公開

    /// ゲーム終了処理。ハイスコア更新を判定し、結果画面へ遷移する。
    private func endGame() {
        // 新記録なら ScoreBoard が保存し true を返す。結果画面の表示に使う
        isNewRecord = ScoreBoard.saveIfBetter(score: score, for: UDKey.pinballHighScore)
        withAnimation(.easeInOut(duration: 0.3)) {
            gameState = .finished
        }
    }
}
