//
//  MakeTenModels.swift
//  FDL-TenBlitz
//
//  Created by 空飛ぶ研究室(FlyingDevLab) on 2026/03/08.
//

// アプリ全体で共有する軽量なデータ型（列挙型・構造体）とUserDefaultsキーを定義するファイル。
// ロジックを持たない純粋なモデル層として、各ViewModel・Viewから参照される。

import SwiftUI

// MARK: - Models
// ゲーム全体で使う列挙型・構造体。

/// ゲームの画面状態
// MakeTenContentViewのコンテンツ切り替え条件として使われる。
// GameViewModelが保持し、遷移メソッド（startGame / returnToTitle）で更新される
enum GameState  { case title, playing, finished }

/// ゲームモード。normal = 30秒、blitz = 10秒
// タイマー上限・ゲージ警告閾値・ポイント倍率などの分岐条件として各所で参照される
enum GameMode   { case normal, blitz }

/// 正解・不正解マークの種別
// GameViewModelがanswerMarkプロパティとして保持し、PlayingViewのフィードバック表示に使われる
enum AnswerMark { case correct, wrong }

/// リセット操作の対象
// 設定画面でユーザーがリセット操作を選んだときに、ダイアログの確認先を特定するために使われる
enum ResetTarget { case highScore, progress }

// MARK: - UserDefaults Keys
// UserDefaults のキー文字列を一元管理する。タイポによるサイレントバグを防ぐ。
// 文字列リテラルを直接書かず必ずここを経由することで、キー名変更時の修正箇所を1か所に絞れる

enum UDKey {
    static let hasAgreedToTerms    = "hasAgreedToTerms"    // 初回同意済みフラグ
    static let isSoundOn           = "isSoundOn"           // サウンドON/OFF設定
    static let isBlitzUnlocked     = "isBlitzUnlocked"     // Blitzモード解放済みフラグ
    static let isHighScoreUnlocked = "isHighScoreUnlocked" // ハイスコア表示解放済みフラグ
    static let blitzHighScore      = "blitzHighScore"      // Blitzモードの歴代最高スコア
    static let questionAttempts    = "questionAttempts"    // 問題番号ごとの出題回数（内部統計）
    static let questionCorrects    = "questionCorrects"    // 問題番号ごとの正解回数（内部統計）
    static let quizMode            = "quizMode"            // 絵文字クイズの選択モード
    static let totalCorrectAllTime = "totalCorrectAllTime" // シール用：累計正解数
    static let stickers            = "stickers"            // シール用：位置データ
    static let isTrashUnlocked     = "isTrashUnlocked"     // シール用：ゴミ箱解放フラグ
    static let mazeHighScore       = "cheeseEscape_hi"              // 迷路ゲームの歴代最高スコア
    static let pinballHighScore    = "fdl_pinball_hi"               // ピンボールの歴代最高スコア
    static let whackHighScore      = "flyingdevlab_mogura_highscore" // モグラ叩きの歴代最高スコア
    static let coinDropHighScore   = "fdl_coindrop_hi"               // コインドロップの歴代最高スコア
}

/// 正解時に画面右下から浮かび上がる絵文字リアクションのモデル
// コンボ達成時にGameViewModelが生成し、PlayingViewがアニメーションで表示する。
// idはUUIDで自動採番されるため、同じ絵文字が複数同時に存在しても一意に識別できる
struct Reaction: Identifiable {
    let id      = UUID()
    let emoji:   String
    let xOffset: CGFloat  // 右端からの横オフセット（ランダムで散らばり演出）
}
