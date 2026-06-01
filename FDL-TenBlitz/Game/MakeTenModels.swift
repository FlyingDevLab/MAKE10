//
//  MakeTenModels.swift
//  FDL-TenBlitz
//
//  Created by 空飛ぶ研究室(FlyingDevLab) on 2026/03/08.
//

// アプリ全体で共有する軽量なデータ型（列挙型・構造体）とUserDefaultsキーを定義するファイル。
// ロジックを持たない純粋なモデル層として、各ViewModel・Viewから参照される。
//
// ★ このファイルの役割 ★
//   「データの形だけ」を定義する場所です。
//   処理・ロジック・画面描画は一切書かず、型の定義だけに徹することで
//   「どんな種類の値が存在するか」をアプリ全体で共有できます。
//
//   定義しているもの:
//     - GameState      … ゲームの画面状態（タイトル / プレイ中 / 終了）
//     - GameMode       … ゲームモード（通常 / Blitz）
//     - AnswerMark     … 正解・不正解マークの種別
//     - ResetTarget    … リセット操作の対象
//     - UDKey          … UserDefaults のキー文字列の一覧
//     - Reaction       … コンボ時に浮かぶ絵文字リアクションのモデル

import SwiftUI

// MARK: - Models
// ゲーム全体で使う列挙型・構造体。

/// ゲームの画面状態を表す列挙型。
/// MakeTenContentView のコンテンツ切り替え条件として使われる。
/// GameViewModel が保持し、遷移メソッド（startGame / returnToTitle）で更新される。
/// ★ 3状態を enum で表す理由 ★
///   Bool（true/false の2択）では「タイトル / プレイ中 / 終了」の3状態を表せません。
///   enum にすることで「この3つ以外の状態はありえない」と型レベルで保証できます。
enum GameState  { case title, playing, finished }

/// ゲームモードを表す列挙型。
/// normal = 30秒モード、blitz = 10秒モード。
/// タイマー上限・ゲージ警告閾値・シールポイント倍率などの分岐条件として各所で参照される。
enum GameMode   { case normal, blitz }

/// 正解・不正解マークの種別を表す列挙型。
/// GameViewModel が answerMark プロパティとして保持し、
/// PlayingView のフィードバック表示（✓ / ✗ アイコン）に使われる。
/// 0.5秒後に nil に戻ることでマークが消える（AnswerMark? のオプショナルで管理）。
enum AnswerMark { case correct, wrong }

/// リセット操作の対象を表す列挙型。
/// 設定画面でユーザーがリセットを選んだときに、
/// 確認ダイアログでどちらのリセットかを特定するために使われる。
/// ★ どちらをリセットするか enum で管理する理由 ★
///   Bool（isResettingHighScore: Bool）などを使うより、
///   「リセットの種類」という概念が明確になり、将来リセット対象が増えても追加しやすい。
enum ResetTarget { case highScore, progress }

// MARK: - UserDefaults Keys
//
// UserDefaults のキー文字列を一元管理する。タイポによるサイレントバグを防ぐ。
// 文字列リテラルを直接書かず必ずここを経由することで、キー名変更時の修正箇所を1か所に絞れる。
//
// ★ サイレントバグとは？ ★
//   クラッシュせず気づきにくいバグのことです。
//   UserDefaults のキーは文字列なので、たとえば
//   "isBlitzUnrocked"（l と r を打ち間違い）と書いても
//   コンパイルエラーにならず、「値が常に保存できていない」という
//   症状が出るだけで原因を探すのが非常に困難です。
//   UDKey.isBlitzUnlocked と書けばコンパイラが typo を検出してくれます。

enum UDKey {
    static let hasAgreedToTerms    = "hasAgreedToTerms"    // 初回同意済みフラグ（同意画面を再表示しないため）
    static let isSoundOn           = "isSoundOn"           // サウンドON/OFF設定
    static let isBlitzUnlocked     = "isBlitzUnlocked"     // Blitzモード解放済みフラグ
    static let isHighScoreUnlocked = "isHighScoreUnlocked" // ハイスコア表示解放済みフラグ
    static let blitzHighScore      = "blitzHighScore"      // Blitzモードの歴代最高スコア
    static let questionAttempts    = "questionAttempts"    // 問題番号ごとの出題回数（内部統計）
    static let questionCorrects    = "questionCorrects"    // 問題番号ごとの正解回数（内部統計）
    static let quizMode            = "quizMode"            // 絵文字クイズの選択モード
    static let totalCorrectAllTime = "totalCorrectAllTime" // シール用：累計正解数（シールポイントの基盤）
    static let stickers            = "stickers"            // シール用：各シールの位置データ
    static let isTrashUnlocked     = "isTrashUnlocked"     // シール用：ゴミ箱機能の解放フラグ
    // ★ ゲームごとにキー名が異なる理由 ★
    //   各ゲームが独立したキー名を使うことで、将来ゲームを切り出して
    //   別アプリにしたとしてもキーの衝突が起きません。
    static let mazeHighScore       = "cheeseEscape_hi"               // 迷路ゲームの歴代最高スコア
    static let pinballHighScore    = "fdl_pinball_hi"                // ピンボールの歴代最高スコア
    static let whackHighScore      = "flyingdevlab_mogura_highscore" // モグラ叩きの歴代最高スコア
    static let coinDropHighScore   = "fdl_coindrop_hi"               // コインドロップの歴代最高スコア
}

// MARK: - Reaction

/// 正解コンボ達成時に画面に浮かび上がる絵文字リアクションのデータモデル。
/// コンボ達成時に GameViewModel が生成し、PlayingView がアニメーションで表示する。
///
/// ★ Identifiable とは？ ★
///   SwiftUI の ForEach でリストを表示するとき、各要素を一意に識別するための
///   プロトコルです。`id` プロパティを持つことで SwiftUI が「どれが追加・削除されたか」を
///   追跡できるようになり、正しくアニメーションが適用されます。
///
/// ★ UUID とは？ ★
///   Universally Unique Identifier（汎用一意識別子）の略。
///   `UUID()` を呼ぶたびに世界中で重複しない一意のIDが生成されます。
///   同じ絵文字（例: "❤️"）が複数同時に画面上に存在する場合でも、
///   UUID で個々の Reaction を正しく識別できます。

struct Reaction: Identifiable {
    /// SwiftUI が個々のリアクションを識別するための一意ID（自動生成）
    let id      = UUID()
    /// 表示する絵文字（GameViewModel の reactionEmojis プールからランダムに選ばれる）
    let emoji:   String
    /// 画面右端からの横方向オフセット（pt）。ランダム値で複数の絵文字が散らばって見える
    let xOffset: CGFloat
}
