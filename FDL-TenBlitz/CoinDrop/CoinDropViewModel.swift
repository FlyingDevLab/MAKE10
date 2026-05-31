//
//  CoinDropViewModel.swift
//  FDL-TenBlitz
//
//  Created by 空飛ぶ研究室(FlyingDevLab) on 2026/05/30.
//

// CoinDrop のアプリレベル状態（スコア・残り時間・次のコイン・画面遷移）を管理する。
// 物理シミュレーション・出現・合体ロジックは CoinDropScene が担い、
// スコア変化／残り秒数／次コイン／ゲームオーバーをコールバックで受け取る。
// PinballViewModel と同じ「Scene は物理、ViewModel は状態」の役割分担。

import SwiftUI

// MARK: - CoinDropGameOverReason
// ゲームオーバーの理由。Scene → ViewModel → 結果画面 で共有する。

enum CoinDropGameOverReason {
    case timeUp    // 時間切れ
    case overflow  // フィールド溢れ
}

// MARK: - CoinType
// コインの種類。rawValue はセント価値。
// 半径・色・ラベル・合体ルールといった「コイン固有のデータ」をここに集約する。
// （重力・反発などの物理パラメータやフィールド寸法は CoinDropScene の CoinDropTuning 側）

enum CoinType: Int, CaseIterable {
    case penny      = 1   // 1¢
    case nickel     = 5   // 5¢
    case dime       = 10  // 10¢
    case quarter    = 25  // 25¢
    case halfDollar = 50  // 50¢

    /// コイン上に表示する短いラベル
    var label: String {
        switch self {
        case .penny:      return "1¢"
        case .nickel:     return "5¢"
        case .dime:       return "10¢"
        case .quarter:    return "25¢"
        case .halfDollar: return "50¢"
        }
    }

    /// ゲーム内半径(pt)。子どもが掴みやすいよう実寸比よりやや大きめにスケール。
    /// ※要調整値（CoinDrop_Spec の「実装時に要調整」に対応）
    var radius: CGFloat {
        switch self {
        case .penny:      return 50
        case .nickel:     return 56
        case .dime:       return 46   // 最小
        case .quarter:    return 64
        case .halfDollar: return 80
        }
    }

    /// SpriteKit 用のコイン色
    var uiColor: UIColor {
        switch self {
        case .penny:      return UIColor(red: 0.82, green: 0.53, blue: 0.27, alpha: 1) // 銅色
        case .nickel:     return UIColor(red: 0.78, green: 0.79, blue: 0.82, alpha: 1) // 銀色（明）
        case .dime:       return UIColor(red: 0.70, green: 0.72, blue: 0.76, alpha: 1) // 銀色（暗）
        case .quarter:    return UIColor(red: 0.74, green: 0.76, blue: 0.80, alpha: 1) // 銀色
        case .halfDollar: return UIColor(red: 0.88, green: 0.78, blue: 0.42, alpha: 1) // 金寄り（$を作る特別コイン）
        }
    }

    /// SwiftUI 用（NEXT プレビュー等）
    var color: Color { Color(uiColor: uiColor) }

    /// コイン内ラベルの文字色（コントラスト確保）
    var labelUIColor: UIColor {
        switch self {
        case .penny:      return .white
        default:          return UIColor(white: 0.18, alpha: 1)
        }
    }

    /// 合体に必要な同種コインの枚数
    var mergeCount: Int {
        switch self {
        case .penny:      return 5  // 1¢×5  → 5¢
        case .nickel:     return 2  // 5¢×2  → 10¢
        case .dime:       return 5  // 10¢×5 → 50¢
        case .quarter:    return 2  // 25¢×2 → 50¢
        case .halfDollar: return 2  // 50¢×2 → $1
        }
    }

    /// 合体後のコイン。nil の場合は $1 として消滅し、スコア+1。
    var mergesInto: CoinType? {
        switch self {
        case .penny:      return .nickel
        case .nickel:     return .dime
        case .dime:       return .halfDollar
        case .quarter:    return .halfDollar
        case .halfDollar: return nil
        }
    }
}

// MARK: - CoinDropViewModel

@Observable
final class CoinDropViewModel {

    enum GameState { case title, playing, finished }

    var gameState:      GameState             = .title
    var score:          Int                   = 0
    var displaySeconds: Int                   = Int(CoinDropTuning.gameDuration)
    var nextCoin:       CoinType              = .penny
    var gameOverReason: CoinDropGameOverReason = .timeUp
    var isNewRecord:    Bool                  = false

    /// $10（MAKE10）到達で達成扱い
    var isPerfect: Bool { score >= 10 }

    var highScore: Int {
        UserDefaults.standard.integer(forKey: UDKey.coinDropHighScore)
    }

    // MARK: - Game Control

    func startGame() {
        score          = 0
        displaySeconds = Int(CoinDropTuning.gameDuration)
        nextCoin       = .penny
        isNewRecord    = false
        gameState      = .playing
    }

    func returnToTitle() {
        gameState = .title
    }

    // MARK: - Callbacks from CoinDropScene

    /// スコア変化（$1 完成ごと）
    func updateScore(_ newScore: Int) {
        score = newScore
    }

    /// 残り秒数（整数が変化したときのみ Scene から呼ばれる）
    func updateSeconds(_ seconds: Int) {
        displaySeconds = seconds
    }

    /// 次に落ちてくるコイン（プレビュー用）
    func updateNextCoin(_ type: CoinType) {
        nextCoin = type
    }

    /// ゲームオーバー（時間切れ／溢れ）
    func gameOver(reason: CoinDropGameOverReason) {
        guard gameState == .playing else { return }
        gameOverReason = reason
        isNewRecord    = checkAndSaveHighScore(score)
        withAnimation(.easeInOut(duration: 0.3)) {
            gameState = .finished
        }
    }

    // MARK: - Private

    private func checkAndSaveHighScore(_ current: Int) -> Bool {
        let prev = UserDefaults.standard.integer(forKey: UDKey.coinDropHighScore)
        guard current > prev else { return false }
        UserDefaults.standard.set(current, forKey: UDKey.coinDropHighScore)
        return true
    }
}
