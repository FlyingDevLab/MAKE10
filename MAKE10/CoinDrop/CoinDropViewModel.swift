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
//
// ★ ViewModel とは？ ★
//   MVVM（Model-View-ViewModel）パターンにおける ViewModel は
//   「画面に何を表示するか」を管理する層です。
//   View（画面）は ViewModel の値を表示するだけで、
//   ロジック（計算・保存など）は ViewModel が担います。
//   こうすることで View がシンプルになり、テストや改修がしやすくなります。
//
// ★ このファイルで定義するもの ★
//   1. CoinDropGameOverReason … ゲームオーバーの理由（列挙型）
//   2. CoinType               … コインの種類と固有データ（列挙型）
//   3. CoinDropViewModel      … ゲーム状態の管理クラス

import SwiftUI

// MARK: - CoinDropGameOverReason
//
// ゲームオーバーになった理由を表す列挙型。
// CoinDropScene（物理）→ CoinDropViewModel（状態）→ CDResultView（表示）
// という流れで受け渡される。
//
// ★ enum（列挙型）とは？ ★
//   決まった種類の値だけを取れる型です。
//   Bool は true/false の2択ですが、enum は3種類以上の選択肢を表せます。
//   「時間切れ」と「溢れ」以外の理由は絶対に来ない、と型レベルで保証できます。

enum CoinDropGameOverReason {
    case timeUp    // 制限時間が 0 になった
    case overflow  // コインが危険ラインを超えて静止した（フィールドが溢れた）
}

// MARK: - CoinType
//
// コインの種類を表す列挙型。rawValue はセント価値（整数）。
// 半径・色・ラベル・合体ルールといった「コイン固有のデータ」をここに集約する。
// （重力・反発などの物理パラメータやフィールド寸法は CoinDropScene 側の CoinDropTuning）
//
// ★ rawValue とは？ ★
//   enum に「: Int」を付けると、各 case に整数の生の値（rawValue）が割り当てられます。
//   ここでは penny = 1（1セント）, nickel = 5（5セント）のように
//   コインの実際の価値をそのまま rawValue として使っています。
//
// ★ CaseIterable とは？ ★
//   準拠すると CoinType.allCases という「全 case の配列」が自動生成されます。
//   CoinDropScene の scanAndMergeOnce() で全種を順番にスキャンするときに使います。

enum CoinType: Int, CaseIterable {
    case penny      = 1   // 1¢  アメリカの1セント硬貨（銅色）
    case nickel     = 5   // 5¢  5セント硬貨（銀色）
    case dime       = 10  // 10¢ 10セント硬貨（最も小さく薄い）
    case quarter    = 25  // 25¢ 25セント硬貨（最もよく使われる）
    case halfDollar = 50  // 50¢ 50セント硬貨（金寄りの色・合体すると $1 になる特別コイン）

    // MARK: ラベル

    /// コインの表面に表示する短いテキスト（例: "1¢"）
    var label: String {
        switch self {
        case .penny:      return "1¢"
        case .nickel:     return "5¢"
        case .dime:       return "10¢"
        case .quarter:    return "25¢"
        case .halfDollar: return "50¢"
        }
    }

    // MARK: サイズ

    /// SpriteKit シーン上でのコインの半径（ポイント単位）。
    /// 子どもが指で掴みやすいよう、実寸比よりやや大きめにスケールしている。
    /// ※ dime（10¢）は現実でも最小のコインなので、ゲーム内でも一番小さい半径 46pt。
    var radius: CGFloat {
        switch self {
        case .penny:      return 50
        case .nickel:     return 56
        case .dime:       return 46   // 最小（現実の dime に合わせた設定）
        case .quarter:    return 64
        case .halfDollar: return 80   // 最大（$1 の手前なので存在感を出す）
        }
    }

    // MARK: 色

    /// SpriteKit（UIKit ベース）で使うコインの色。
    /// UIColor の (red:green:blue:alpha:) は各チャンネルを 0.0〜1.0 で指定する。
    var uiColor: UIColor {
        switch self {
        case .penny:      return UIColor(red: 0.82, green: 0.53, blue: 0.27, alpha: 1) // 銅色
        case .nickel:     return UIColor(red: 0.78, green: 0.79, blue: 0.82, alpha: 1) // 銀色（明）
        case .dime:       return UIColor(red: 0.70, green: 0.72, blue: 0.76, alpha: 1) // 銀色（暗）
        case .quarter:    return UIColor(red: 0.74, green: 0.76, blue: 0.80, alpha: 1) // 銀色
        case .halfDollar: return UIColor(red: 0.88, green: 0.78, blue: 0.42, alpha: 1) // 金寄り（$1 を作る特別コイン）
        }
    }

    /// SwiftUI（NEXT プレビュー・CoinChip など）で使うコインの色。
    /// UIColor → Color への変換は SwiftUI の標準イニシャライザで行う。
    var color: Color { Color(uiColor: uiColor) }

    /// コイン内ラベル（"1¢" など）の文字色。
    /// 背景色との明度差を確保してコントラストを保つための設定。
    /// penny（銅色）は暗めなので白、それ以外（銀・金）は明るいので黒寄りの色にする。
    var labelUIColor: UIColor {
        switch self {
        case .penny:      return .white
        default:          return UIColor(white: 0.18, alpha: 1)  // ほぼ黒
        }
    }

    // MARK: 合体ルール

    /// 合体に必要な同種コインの枚数。
    /// この枚数が隣接して揃うと自動で次のコインに変化する。
    var mergeCount: Int {
        switch self {
        case .penny:      return 5  // 1¢ × 5  →  5¢
        case .nickel:     return 2  // 5¢ × 2  → 10¢
        case .dime:       return 5  // 10¢ × 5 → 50¢
        case .quarter:    return 2  // 25¢ × 2 → 50¢
        case .halfDollar: return 2  // 50¢ × 2 → $1（スコア +1）
        }
    }

    /// 合体後に変化するコインの種類。
    /// nil の場合は「最上位コインの合体 = $1 完成」を意味し、
    /// コインは消滅してスコアが 1 加算される。
    /// （CoinDropScene の performMerge で if let into else で分岐している）
    var mergesInto: CoinType? {
        switch self {
        case .penny:      return .nickel       // 1¢ → 5¢
        case .nickel:     return .dime         // 5¢ → 10¢
        case .dime:       return .halfDollar   // 10¢ → 50¢
        case .quarter:    return .halfDollar   // 25¢ → 50¢
        case .halfDollar: return nil           // 50¢ → $1（消滅・スコア加算）
        }
    }
}

// MARK: - CoinDropViewModel
//
// ゲームの「状態」を一元管理するクラス。
// View はこのクラスの値を表示するだけで、値を変える処理はすべてここに集まる。
//
// ★ @Observable とは？ ★
//   Swift 5.9 以降の Observation フレームワークが提供するマクロです。
//   クラスに付けると、プロパティの変化を SwiftUI が自動で検知して画面を再描画します。
//   以前の @ObservableObject + @Published の組み合わせを簡略化したものです。
//
// ★ final とは？ ★
//   このクラスをさらにサブクラス化（継承）できないという宣言です。
//   継承される想定がないことを明示し、コンパイラの最適化も効きやすくなります。

@Observable
final class CoinDropViewModel {

    // MARK: - GameState

    /// 画面の状態を表す列挙型（ファイル内で定義し、VM だけが使う）
    /// .title    → タイトル画面（CDTitleView）
    /// .playing  → ゲーム中（CDPlayingView）
    /// .finished → リザルト画面（CDResultView）
    enum GameState { case title, playing, finished }

    // MARK: - Published プロパティ（View に表示される値）
    //
    // @Observable クラスの var プロパティは自動的に監視対象になる。
    // 値が変わると、それを参照している View が自動で再描画される。

    /// 現在の画面状態（タイトル / プレイ中 / リザルト）
    var gameState:      GameState             = .title

    /// $1 を完成させた回数（= ゲームのスコア）
    var score:          Int                   = 0

    /// HUD に表示する残り秒数（Scene から整数が変化したときだけ更新される）
    var displaySeconds: Int                   = Int(CoinDropTuning.gameDuration)

    /// HUD の NEXT エリアに表示する「次に落ちてくるコイン」
    var nextCoin:       CoinType              = .penny

    /// ゲームオーバーの理由（リザルト画面での文言切り替えに使う）
    var gameOverReason: CoinDropGameOverReason = .timeUp

    /// 今回のゲームで自己ベストを更新したかどうか
    var isNewRecord:    Bool                  = false

    // MARK: - 計算プロパティ

    /// $10（= $1 を 10 回完成）以上で MAKE10 達成
    /// ★ 計算プロパティ = 毎回 score から計算するだけ。保存する必要がない値に向く
    var isPerfect: Bool { score >= 10 }

    /// 歴代最高スコア。ScoreBoard 経由で読み取る。
    var highScore: Int { ScoreBoard.highScore(for: UDKey.coinDropHighScore) }

    // MARK: - Game Control
    //
    // ゲームの流れ：
    //   startGame() → .playing → Scene がコールバックで状態を送る
    //              → gameOver() → .finished → returnToTitle() or startGame()

    /// ゲームを（再）開始する。スコアなどをリセットして .playing に移行する。
    func startGame() {
        score          = 0
        displaySeconds = Int(CoinDropTuning.gameDuration)
        nextCoin       = .penny
        isNewRecord    = false
        gameState      = .playing  // View 側が .playing に切り替わり CDPlayingView が表示される
    }

    /// タイトル画面へ戻る
    func returnToTitle() {
        gameState = .title
    }

    // MARK: - Callbacks from CoinDropScene
    //
    // これらのメソッドは CoinDropScene（物理の世界）から呼ばれる。
    // Scene は「ゲームの出来事」だけを通知し、表示への影響は VM が制御する。
    // こうすることで Scene が UI を直接触らなくて済む（責任の分離）。

    /// $1 が完成してスコアが変化したとき Scene から呼ばれる
    func updateScore(_ newScore: Int) {
        score = newScore
    }

    /// 残り秒数が1秒変化したとき Scene から呼ばれる（毎フレームではない）
    func updateSeconds(_ seconds: Int) {
        displaySeconds = seconds
    }

    /// 次に落ちてくるコインが変わったとき Scene から呼ばれる（プレビュー更新）
    func updateNextCoin(_ type: CoinType) {
        nextCoin = type
    }

    /// ゲームオーバーが発生したとき Scene から呼ばれる
    /// - Parameter reason: 終了理由（.timeUp or .overflow）
    func gameOver(reason: CoinDropGameOverReason) {
        // .playing 以外の状態（例: 既にリザルト表示中）では無視する（二重呼び出し防止）
        guard gameState == .playing else { return }
        gameOverReason = reason
        // 新記録なら ScoreBoard が保存し true を返す。結果画面の表示に使う
        isNewRecord    = ScoreBoard.saveIfBetter(score: score, for: UDKey.coinDropHighScore)
        // withAnimation でリザルト画面への切り替えにアニメーションをかける
        withAnimation(.easeInOut(duration: 0.3)) {
            gameState = .finished
        }
    }
}
