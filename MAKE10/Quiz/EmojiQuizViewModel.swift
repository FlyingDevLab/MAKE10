//
//  EmojiQuizViewModel.swift
//  FDL-TenBlitz
//
//  Created by 空飛ぶ研究室(FlyingDevLab) on 2026/03/08.
//

// 絵文字クイズのゲーム状態を管理するViewModelと、回答状態を表す列挙型を定義するファイル。
// 問題生成・回答処理・自動進行・リスタートをすべてこのクラスが担う。
//
// ★ このファイルの構成 ★
//   AnswerState        … 1問に対する回答状態（未回答 / 正解 / 不正解）
//   EmojiQuizViewModel … クイズ1セッションの頭脳
//
// 役割分担:
//   - EmojiQuizViewModel（このファイル）: 問題生成・正誤判定・スコア・進行制御
//   - QuizPlayingContent (EmojiQuizHomeView.swift) : プレイ中のUI表示
//   - EmojiQuizResultView                          : 結果画面のUI表示

import SwiftUI

// MARK: - AnswerState

/// 各問題に対するプレイヤーの回答状態を表す列挙型。
/// UIの選択肢ボタン・フィードバックラベル・次問ボタンの表示制御に使われる。
enum AnswerState {
    case unanswered, correct, wrong
}

// MARK: - EmojiQuizViewModel

// @Observable の解説は AppSettings.swift 冒頭を参照。
//
// ★ @MainActor とは？ ★
//   このクラスのプロパティ変更・メソッド実行をすべて「メインスレッド」で
//   行うことをコンパイラに保証させる属性です。
//   UIの更新はメインスレッドからしか行えないというiOSの大原則があり、
//   @Observable なプロパティは変更がそのままUI更新につながるため、
//   クラスごとメインスレッドに固定しておくのが安全です。
//   （GameViewModel は asyncAfter(メインキュー指定)で同じことを手動でやっています）

@Observable
@MainActor
final class EmojiQuizViewModel {

    // MARK: 設定値（開始時に確定）

    // ゲーム開始時に確定する不変のパラメータ。開始後は変更されない
    let category:   QuizCategory  // 出題元のカテゴリ（問題プールとdisplayStyleを持つ）
    let mode:       QuizMode      // 出題モード（絵文字→テキスト or テキスト→絵文字）
    let totalCount: Int           // 1セッションの総問題数（通常10問）

    // MARK: 進行状態

    // ゲームの進行状態。Viewはこれらを監視してUIを更新する

    /// 今回のセッションで出題される問題リスト。
    var questions:    [QuizQuestion] = []
    /// 現在表示中の問題インデックス（0始まり）。
    var currentIndex: Int            = 0
    /// 現在の正解数。
    var score:        Int            = 0
    /// 現在の問題に対する回答状態。
    var answerState:  AnswerState    = .unanswered
    /// プレイヤーが選択した選択肢（フィードバック表示に使用）。
    var selectedItem: QuizItem?      = nil
    /// 全問回答完了フラグ。true になると結果画面に切り替わる。
    var isFinished:   Bool           = false
    /// 各問題の正誤記録。進捗ドットの色付けに使用。
    var results:      [Bool]         = []

    // MARK: 自動進行タスク

    /// 正解時の自動進行タスクを保持する。不正解時や早期操作時にキャンセルするために参照を保持する。
    ///
    /// ★ Task（Swift Concurrency）とは？ ★
    ///   Task { ... } は非同期処理のかたまりを作る Swift の仕組みで、
    ///   await Task.sleep で「指定時間待ってから続きを実行」できます。
    ///   ポイントは cancel() を呼ぶと中断できること。
    ///   「古い遅延処理が後から発火して状態を壊す」問題への対策として、
    ///   GameViewModel では世代番号パターン（番号の不一致で無視）を使いましたが、
    ///   ここでは Task の保持とキャンセルという別解で同じ問題を解いています。
    ///   キャンセル対象が1つだけならこちらの方がシンプルです。
    private var autoAdvanceTask: Task<Void, Never>?

    // MARK: 算出プロパティ

    /// 現在表示すべき問題を返す。インデックスが範囲外のときは nil を返す（境界安全）。
    var currentQuestion: QuizQuestion? {
        guard currentIndex < questions.count else { return nil }
        return questions[currentIndex]
    }

    /// 「1 / 10」形式の進捗テキスト。View はこれを ProgressSection に表示する。
    var progressText: String { "\(currentIndex + 1) / \(totalCount)" }

    // MARK: 初期化

    /// カテゴリ・モード・問題数を受け取り、即座に問題を生成して開始できる状態にする。
    init(category: QuizCategory, mode: QuizMode, totalCount: Int = 10) {   // ← 変更可（1セッションの問題数）
        self.category   = category
        self.mode       = mode
        self.totalCount = totalCount
        buildQuestions()
    }

    // MARK: 問題生成

    /// カテゴリのアイテムプールをシャッフルして totalCount 問を抽出し、
    /// 各問題に正解1つ＋ランダムな不正解3つの選択肢セットを生成する。
    /// 同一プールから選択肢を作るため、全選択肢がカテゴリ内の実在アイテムになる。
    private func buildQuestions() {
        let pool   = category.items.shuffled()
        let picked = Array(pool.prefix(totalCount))
        questions  = picked.map { correct in
            // 正解以外からランダムに3つ選んで不正解選択肢にする
            let others  = pool.filter { $0.id != correct.id }.shuffled().prefix(3)
            // 正解と不正解を混ぜてシャッフルし、正解が毎回同じ位置に来ないようにする
            let choices = ([correct] + others).shuffled()
            return QuizQuestion(correct: correct, choices: choices)
        }
        // results を false で初期化しておき、回答のたびに上書きする
        results = Array(repeating: false, count: questions.count)
    }

    // MARK: 回答処理

    /// 選択肢がタップされたときの処理。二重回答防止のため .unanswered のときのみ受け付ける。
    func select(_ item: QuizItem) {
        guard answerState == .unanswered,
              let q = currentQuestion else { return }

        selectedItem  = item
        let isCorrect = item.id == q.correct.id
        answerState   = isCorrect ? .correct : .wrong

        if isCorrect {
            score += 1
            // textToEmoji モードは難易度が高いため、シールポイントを高く設定している
            StickerStore.shared.recordCorrect(points: mode == .textToEmoji ? 1.9 : 1.4)  // ← 変更可（難しい:1.9pt / 基本:1.4pt）
        }
        results[currentIndex] = isCorrect

        // 正誤に応じたバイブと効果音を再生する
        SoundManager.shared.vibrate()
        isCorrect ? SoundManager.shared.playCorrect() : SoundManager.shared.playWrong()

        // 正解時は1.4秒後に自動で次の問題へ進む。
        // [weak self] でメモリリークを防ぎ、Task.isCancelled でキャンセルチェックを行う
        // （[weak self] の解説は GameViewModel.swift を参照）
        autoAdvanceTask = Task { @MainActor [weak self] in
            // ← 変更可：自動進行までの待機時間。単位はナノ秒（1_400_000_000 = 1.4秒）
            try? await Task.sleep(nanoseconds: 1_400_000_000)
            guard let self, !Task.isCancelled else { return }
            if isCorrect { self.advance() }
        }
    }

    // MARK: 進行

    /// 次の問題へ進むか、最終問題なら終了処理を行う内部メソッド。
    /// select() の自動進行タスクと nextQuestion() の両方から呼ばれる。
    private func advance() {
        if currentIndex + 1 >= questions.count {
            // 全問回答完了。正答率に応じた効果音を再生する
            let pct = totalCount > 0 ? Double(score) / Double(totalCount) : 0
            switch pct {
            case 1.0:    SoundManager.shared.playSpecial()   // 100%達成
            case 0.8...: SoundManager.shared.playTenClear()  // 80%以上 ← 変更可（特別音の閾値）
            default:     SoundManager.shared.playGameOver()  // 80%未満
            }
            // 全問正解でステッカーを1枚追加（リザルト画面で表示・確定される）
            if pct == 1.0 { StickerStore.shared.addBonusSticker() }
            isFinished = true
        } else {
            // 次の問題へ。answerState と selectedItem をリセットして未回答状態に戻す
            currentIndex += 1
            answerState  = .unanswered
            selectedItem = nil
        }
    }

    /// 不正解時に表示される「つぎのもんだい」ボタンから呼ばれるメソッド。
    /// 自動進行タスクをキャンセルしてから advance() を呼ぶことで二重進行を防ぐ。
    func nextQuestion() {
        autoAdvanceTask?.cancel()
        advance()
    }

    // MARK: リスタート

    /// ゲームを最初からやり直す。全状態を初期値にリセットしてから問題を再生成する。
    /// 自動進行タスクが残っている場合はキャンセルしてからリセットする。
    func restart() {
        autoAdvanceTask?.cancel()
        currentIndex = 0
        score        = 0
        answerState  = .unanswered
        selectedItem = nil
        isFinished   = false
        buildQuestions()
    }
}
