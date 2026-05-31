//
//  QuizData.swift
//  FDL-TenBlitz
//
//  Created by 空飛ぶ研究室(FlyingDevLab) on 2026/03/08.
//

// 絵文字クイズで使うデータモデルをすべて定義するファイル。
// DisplayStyle・QuizMode・QuizCategory・QuizItem・QuizQuestionの5つで
// 「カテゴリ → 問題 → 選択肢」の階層構造を表現する。

import Foundation

// MARK: - Display Style
// クイズの選択肢・問題文の表示形式を定義する。
// .emoji: 絵文字表示（動物・国旗など）
// .code:  等幅テキスト（空港コードなど）
// .text:  丸ゴシックテキスト（漢字・英単語など）

// QuizCategoryごとに1つのDisplayStyleを持ち、問題カードと選択肢グリッドの描画を切り替える。
// QuizMode × DisplayStyle の組み合わせでUIラベルも変わるため、QuizModeのメソッドにも渡される
enum DisplayStyle {
    case emoji
    case code
    case text
}

// MARK: - Quiz Mode

// クイズの出題方向を表す列挙型。rawValueはUserDefaultsへの永続化キーとして使われる。
// CaseIterableに準拠することでホーム画面のモード選択行をForEachで生成できる
enum QuizMode: String, CaseIterable {
    case emojiToText = "emojiToText"  // 絵文字（またはコード・テキスト）を見て名前を答える
    case textToEmoji = "textToEmoji"  // 名前を見て絵文字（またはコード・テキスト）を答える

    // ホーム画面のモード選択行に表示する主ラベル。
    // QuizMode × DisplayStyle の6通りに対応するローカライズ文字列を返す
    func primaryLabel(for style: DisplayStyle) -> String {
        switch (self, style) {
        case (.emojiToText, .emoji): return String(localized: "quiz_mode_emoji_to_text")
        case (.emojiToText, .code):  return String(localized: "quiz_mode_code_to_name")
        case (.emojiToText, .text):  return String(localized: "quiz_mode_char_to_reading")
        case (.textToEmoji, .emoji): return String(localized: "quiz_mode_text_to_emoji")
        case (.textToEmoji, .code):  return String(localized: "quiz_mode_name_to_code")
        case (.textToEmoji, .text):  return String(localized: "quiz_mode_reading_to_char")
        }
    }

    // ホーム画面のモード選択行に表示する補足説明ラベル（primaryLabelの下に小さく表示）
    func descriptionLabel(for style: DisplayStyle) -> String {
        switch (self, style) {
        case (.emojiToText, .emoji): return String(localized: "quiz_desc_emoji_to_text")
        case (.emojiToText, .code):  return String(localized: "quiz_desc_code_to_name")
        case (.emojiToText, .text):  return String(localized: "quiz_desc_char_to_reading")
        case (.textToEmoji, .emoji): return String(localized: "quiz_desc_text_to_emoji")
        case (.textToEmoji, .code):  return String(localized: "quiz_desc_name_to_code")
        case (.textToEmoji, .text):  return String(localized: "quiz_desc_reading_to_char")
        }
    }

    // 問題カード下部に表示する「なにをこたえる？」の誘導テキスト。
    // primaryLabelより短く、プレイ中に視線が自然に流れる位置に表示される
    func questionLabel(for style: DisplayStyle) -> String {
        switch (self, style) {
        case (.emojiToText, .emoji): return String(localized: "quiz_question_emoji_to_text")
        case (.emojiToText, .code):  return String(localized: "quiz_question_code_to_name")
        case (.emojiToText, .text):  return String(localized: "quiz_question_char_to_reading")
        case (.textToEmoji, .emoji): return String(localized: "quiz_question_text_to_emoji")
        case (.textToEmoji, .code):  return String(localized: "quiz_question_name_to_code")
        case (.textToEmoji, .text):  return String(localized: "quiz_question_reading_to_char")
        }
    }
}

// MARK: - Quiz Category

// カテゴリ1件のデータモデル。QuizCategoryLoaderがJSONから生成して返す。
// Equatableの==はidのみで比較する。itemsの内容が異なっても同じIDなら同一カテゴリとみなす
struct QuizCategory: Identifiable, Equatable {
    let id: String          // JSONのgameIdと一致する一意な識別子
    let group: String       // カテゴリグループ名（ホーム画面のセクション見出しに使用）
    let title: String       // カテゴリ名（ホーム画面の行とヘッダータイトルに使用）
    let icon: String        // カテゴリ一覧に表示するアイコン絵文字
    let displayStyle: DisplayStyle  // このカテゴリの問題・選択肢の表示形式
    let items: [QuizItem]   // このカテゴリに属する全問題アイテムのプール

    static func == (lhs: QuizCategory, rhs: QuizCategory) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Quiz Item
// id は UUID() で常にユニーク。buildQuestions() で choices 配列に correct の
// 同一インスタンスが含まれるため、id 比較で正誤判定が成立する。

// 絵文字クイズの問題1件を構成するアイテム。正解としても選択肢としても使われる。
// UUIDによるidで同じ絵文字や同じ名前のアイテムが複数存在しても区別できる
struct QuizItem: Identifiable, Equatable {
    let id    = UUID()
    let emoji: String   // 表示用（絵文字 / コード / テキスト）
    let name:  String   // よみかた / 空港名 / 意味など
}

// MARK: - Quiz Question

// 1問分の問題データ。正解アイテム1つとシャッフル済みの選択肢4つを持つ。
// EmojiQuizViewModelのbuildQuestions()で生成され、セッション中は変更されない
struct QuizQuestion {
    let correct: QuizItem    // 正解のアイテム。choices配列の中にも含まれている
    let choices: [QuizItem]  // 正解1つ＋不正解3つをシャッフルした選択肢リスト
}
