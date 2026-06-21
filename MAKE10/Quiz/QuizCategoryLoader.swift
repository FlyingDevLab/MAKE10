//
//  QuizCategoryLoader.swift
//  FDL-TenBlitz
//
//  Created by 空飛ぶ研究室(FlyingDevLab) on 2026/03/08.
//
//  【カテゴリ追加の手順】
//  1. Resources/Quiz/ に {gameId}.json を追加
//  2. quiz_categories.json の配列に gameId を追加
//  3. Swiftコードは一切変更不要
//
//  【言語追加の手順】
//  1. 各 {gameId}.json の name / group / title に言語コードキーを追加するだけ
//  2. Swiftコードは一切変更不要

// JSONファイルからクイズカテゴリを読み込み、アプリ内モデルに変換するローダー。
// 初回読み込み結果をクラス変数にキャッシュし、2回目以降はJSONアクセスを省略する。
// カテゴリの追加・言語の追加はJSONファイルの変更のみで完結し、Swiftコードの変更は不要。
//
// ★ このファイルの構成 ★
//   CategoryJSON       … カテゴリ1件分のJSONデコード用モデル（private）
//   L10nString         … 任意の言語コード辞書を読むローカライズ文字列（private）
//   ItemJSON           … アイテム1件分のJSONデコード用モデル（private）
//   QuizCategoryLoader … ロードとキャッシュを担う本体
//
// Codable（JSONEncoder / JSONDecoder）の解説は GamePickerComponents.swift を参照。

import Foundation

// MARK: - CategoryJSON

// JSONのデコード専用の内部モデル群。このファイル外には公開しない。
// アプリ内で使う QuizCategory / QuizItem への変換は build() メソッドが担う。

/// カテゴリ1件分のJSONをデコードするモデル。
/// composedOf が nil なら独立カテゴリ、配列があれば他カテゴリを結合した合成カテゴリを表す。
private struct CategoryJSON: Codable {
    let gameId:      String
    let group:       L10nString   // 表示グループ名（多言語対応）
    let title:       L10nString   // カテゴリ名（多言語対応）
    let icon:        String       // カテゴリ一覧に表示するアイコン絵文字
    let displayStyle: String      // 問題の表示形式（"emoji" / "code" / "text"）
    let composedOf:  [String]?    // 合成カテゴリの依存先gameId一覧。nilなら独立カテゴリ
    let items:       [ItemJSON]?  // 独立カテゴリのアイテムリスト。合成カテゴリはnil
}

// MARK: - L10nString

/// 任意の言語コードをキーとするローカライズ文字列。
/// JSONの {"ja": "...", "en": "...", "de": "..."} 形式を辞書として読み込む。
/// 新言語の追加はJSONへのキー追加のみで完結し、Swiftコードの変更は不要。
///
/// ★ カスタムデコード（init(from:)）とは？ ★
///   通常の Codable はプロパティ名とJSONのキー名を1対1で対応させますが、
///   ここではキーが「言語コード」で固定されていません（ja / en / de / ... と可変）。
///   そこで init(from:) を自分で書き、singleValueContainer で
///   値全体を [String: String] の辞書として丸ごと読み込んでいます。
///   「キーが事前に決まらないJSON」を読むときの定番テクニックです。
private struct L10nString: Codable {

    private let translations: [String: String]

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        translations = try container.decode([String: String].self)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(translations)
    }

    /// デバイスの優先言語コードに対応する文字列を返す。
    /// 完全一致 → 言語プレフィックス一致 → 英語フォールバック の順で解決する。
    /// 例: "zh-TW" → "zh-Hant" が見つかれば採用、なければ "zh" を試し、最後に "en"
    func value(for langCode: String) -> String {
        // 完全一致（例: "zh-Hans", "pt-BR"）
        if let v = translations[langCode] { return v }

        // 地域サブタグを含む場合の追加試行
        // "zh-TW" → "zh-Hant"、"zh-CN" → "zh-Hans" のような慣用マッピング
        let subtag = langCode.components(separatedBy: "-")
        if subtag.count >= 2 {
            let region = subtag[1]
            // 繁体字中国語の慣用コード
            if subtag[0] == "zh" && ["TW", "HK", "MO"].contains(region),
               let v = translations["zh-Hant"] { return v }
            // 簡体字中国語の慣用コード
            if subtag[0] == "zh" && region == "CN",
               let v = translations["zh-Hans"] { return v }
            // ポルトガル語: pt-PT → pt-BR にフォールバック
            if subtag[0] == "pt", let v = translations["pt-BR"] { return v }
        }

        // 言語プレフィックスのみで一致（例: "de-AT" → "de"）
        let prefix = subtag[0]
        if let v = translations[prefix] { return v }

        // 英語フォールバック
        return translations["en"] ?? translations.values.first ?? ""
    }
}

// MARK: - ItemJSON

/// アイテム1件分のJSONをデコードするモデル。
/// display は絵文字・コード・テキストなど表示形式に依存した文字列。
private struct ItemJSON: Codable {
    let display: String     // 問題として表示する文字列（絵文字 or コード or テキスト）
    let name:    L10nString // 選択肢・正解表示に使う名称（多言語対応）
}

// MARK: - QuizCategoryLoader

/// クイズカテゴリのロードとキャッシュを担う静的クラス。
/// インスタンス化を想定していないため、すべてのメンバーを static で定義する。
final class QuizCategoryLoader {

    /// ロード済みカテゴリのキャッシュ。nil のときはまだロードされていない状態を表す。
    private static var _cache: [QuizCategory]? = nil

    /// 全カテゴリをロード（初回のみJSONを読む。以後はキャッシュ）。
    static func loadAll() -> [QuizCategory] {
        // キャッシュが存在すればJSONアクセスを省略して即返す
        if let cached = _cache { return cached }

        // quiz_categories.json からカテゴリIDの配列を取得する。
        // このファイルがカテゴリの表示順序のマニフェストを兼ねる。
        //
        // ★ assertionFailure とは？ ★
        //   デバッグビルド（開発中）でのみアプリを停止させて問題を知らせる関数です。
        //   リリースビルドでは何もせず素通りするため、万一ファイルが欠けていても
        //   ユーザーのアプリはクラッシュせず、空のカテゴリ一覧として安全に動き続けます。
        //   「開発中は気づきたい・本番では落としたくない」エラーに使います。
        guard
            let url  = Bundle.main.url(forResource: "quiz_categories", withExtension: "json"),
            let data = try? Data(contentsOf: url),
            let ids  = try? JSONDecoder().decode([String].self, from: data)
        else {
            assertionFailure("quiz_categories.json が見つかりません")
            return []
        }

        // ── Step1: 全JSONをロード ───────────────────────────
        // IDをキーにした Dictionary に格納し、後段のビルドで参照しやすくする
        var jsonByID: [String: CategoryJSON] = [:]
        for id in ids {
            if let json = loadJSON(id: id) { jsonByID[id] = json }
        }

        // ── Step2: composedOf を持たないカテゴリを先にビルド ──
        // 合成カテゴリは独立カテゴリのアイテムを参照するため、依存先を先に解決する必要がある
        var builtByID: [String: QuizCategory] = [:]
        for (id, json) in jsonByID where json.composedOf == nil {
            builtByID[id] = build(from: json, builtSoFar: [:])
        }

        // ── Step3: composedOf を持つカテゴリをビルド ──────────
        // Step2で独立カテゴリがすべて builtByID に入っているため、ここで flatMap で結合できる
        for (id, json) in jsonByID where json.composedOf != nil {
            builtByID[id] = build(from: json, builtSoFar: builtByID)
        }

        // ── Step4: マニフェストの順序を維持して返す ──────────
        // Dictionary は順序を保証しないため、元の ids 配列の順番で compactMap して順序を復元する
        let result = ids.compactMap { builtByID[$0] }
        _cache = result
        return result
    }

    /// キャッシュをクリア（テスト・プレビュー用）。
    /// 本番コードからは呼ばない。Preview や単体テストでクリーンな状態を作るために使用する。
    static func clearCache() { _cache = nil }

    // MARK: 内部ヘルパー

    /// 指定したIDのJSONファイルをBundleから読み込み、CategoryJSON にデコードして返す。
    /// ファイルが見つからない・デコード失敗の場合は nil を返す（呼び出し元でスキップされる）。
    private static func loadJSON(id: String) -> CategoryJSON? {
        guard
            let url  = Bundle.main.url(forResource: id, withExtension: "json"),
            let data = try? Data(contentsOf: url)
        else { return nil }
        return try? JSONDecoder().decode(CategoryJSON.self, from: data)
    }

    /// CategoryJSON をアプリ内モデルの QuizCategory に変換する。
    /// 合成カテゴリの場合は builtSoFar から依存先のアイテムを取得して flatMap で結合する。
    private static func build(
        from json: CategoryJSON,
        builtSoFar: [String: QuizCategory]
    ) -> QuizCategory {

        // デバイスの優先言語コードを取得する。
        // preferredLocalizations はアプリのサポート言語と照合済みのリストを返す。
        // 対応言語がない場合は "en" にフォールバックする。
        let langCode = Bundle.main.preferredLocalizations.first ?? "en"

        // JSON文字列から DisplayStyle 列挙型に変換する。未知の値は .emoji にフォールバックする
        let displayStyle: DisplayStyle
        switch json.displayStyle {
        case "emoji": displayStyle = .emoji
        case "code":  displayStyle = .code
        case "text":  displayStyle = .text
        default:      displayStyle = .emoji
        }

        let items: [QuizItem]
        if let composed = json.composedOf {
            // 合成カテゴリ：依存先のアイテムをフラットに結合
            // compactMap で存在しない依存先IDをスキップし、flatMap で全アイテムを1つの配列にまとめる
            items = composed.compactMap { builtSoFar[$0] }.flatMap { $0.items }
        } else {
            // 独立カテゴリ：JSONの items を QuizItem にマッピングする
            items = (json.items ?? []).map { item in
                QuizItem(
                    emoji: item.display,
                    name:  item.name.value(for: langCode)
                )
            }
        }

        return QuizCategory(
            id:           json.gameId,
            group:        json.group.value(for: langCode),
            title:        json.title.value(for: langCode),
            icon:         json.icon,
            displayStyle: displayStyle,
            items:        items
        )
    }
}
