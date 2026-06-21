//
//  MakeTenModels.swift
//  FDL-TenBlitz
//
//  Created by 空飛ぶ研究室(FlyingDevLab) on 2026/03/08.
//

// アプリ全体で共有する軽量なデータ型（列挙型・構造体）とUserDefaultsキーを定義するファイル。
// ロジックを持たない純粋なモデル層として、各ViewModel・Viewから参照される。
//
// ★ このファイルの構成 ★
//   GameState   … ゲームの画面状態（タイトル / プレイ中 / 結果）
//   GameMode    … ゲームモード（30秒 / 10秒Blitz）
//   AnswerMark  … 正解・不正解マークの種別
//   ResetTarget … リセット操作の対象（設定画面で使用）
//   UDKey       … UserDefaults のキー文字列の一元管理
//   Reaction    … 正解時の絵文字リアクションのモデル

import SwiftUI

// MARK: - 共有モデル

/// ゲームの画面状態。
/// MakeTenContentView のコンテンツ切り替え条件として使われる。
/// GameViewModel が保持し、遷移メソッド（startGame / returnToTitle）で更新される。
enum GameState  { case title, playing, finished }

/// ゲームモード。normal = 30秒、blitz = 10秒。
/// タイマー上限・ゲージ警告閾値・ポイント倍率などの分岐条件として各所で参照される。
enum GameMode   { case normal, blitz }

/// 正解・不正解マークの種別。
/// GameViewModel が answerMark プロパティとして保持し、PlayingView のフィードバック表示に使われる。
enum AnswerMark { case correct, wrong }

/// リセット操作の対象。
/// 設定画面でユーザーがリセット操作を選んだときに、ダイアログの確認先を特定するために使われる。
enum ResetTarget { case highScore, progress }

// MARK: - UserDefaultsキー（UDKey）

// UserDefaults のキー文字列を一元管理する。タイポによるサイレントバグを防ぐ。
// 文字列リテラルを直接書かず必ずここを経由することで、キー名変更時の修正箇所を1か所に絞れる。
// case のない enum を名前空間として使う理由は ScoreBoard.swift 冒頭を参照。
//
// ⚠️ 変更注意: 右辺の「文字列」は絶対に変更しないこと。
//   キー文字列を変えると、既存ユーザーの端末に保存されたデータ
//   （ハイスコア・解放状況・シール等）が読めなくなり、全て初期化されたように見えてしまう。
//   `cheeseEscape_hi` のように命名が不揃いなのは歴史的経緯によるもので、
//   揃えたくても変更できない（左辺の定数名はコード内の呼び名なので変更してよい）。
//
// 新ゲームのスコア・ベストタイム用キーを追加したときは、
// ScoreBoard.swift の allScoreKeys にも必ず追加すること（リセット対象に含めるため）。

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
    static let stickers            = "stickers"            // シール用：ゲームモード位置データ（既存キー維持）
    static let storageEmojis       = "storageEmojis"       // シール用：ストレージ絵文字リスト
    static let playStickers        = "playStickers"        // シール用：シール画面位置データ
    static let playBoardBackground = "playBoardBackground" // シール用：シール画面背景色インデックス
    static let mazeHighScore          = "cheeseEscape_hi"              // 迷路ゲームの歴代最高スコア
    static let pinballHighScore       = "fdl_pinball_hi"               // ピンボールの歴代最高スコア
    static let whackHighScore         = "flyingdevlab_mogura_highscore" // モグラ叩きの歴代最高スコア
    static let coinDropHighScore      = "fdl_coindrop_hi"               // コインドロップの歴代最高スコア
    static let jankenBestTimeEasy     = "janken_best_time_easy"         // じゃんけん：Easyベストタイム
    static let jankenBestTimeHard     = "janken_best_time_hard"         // じゃんけん：Hardベストタイム
    static let jankenBestTimeChallenge = "janken_best_time_challenge"   // じゃんけん：Challengeベストタイム
}

// MARK: - Reaction

/// 正解時に画面右下から浮かび上がる絵文字リアクションのモデル。
/// コンボ達成時に GameViewModel が生成し、PlayingView がアニメーションで表示する。
/// id は UUID で自動採番されるため、同じ絵文字が複数同時に存在しても一意に識別できる。
struct Reaction: Identifiable {
    let id      = UUID()
    let emoji:   String
    let xOffset: CGFloat  // 右端からの横オフセット（ランダムで散らばり演出）
}
