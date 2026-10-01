//
//  StickerStore.swift
//  FDL-TenBlitz
//
//  Created by 空飛ぶ研究室(FlyingDevLab) on 2026/03/21.
//
//  手に入れた絵文字シールの保管・配置・永続化を担う。
//  シールはゲームで貯めたエネルギー（EnergyStore）を使い、ガチャ（StickerGacha）か
//  ショップ（StickerShop）で手に入れる。手に入れたシールはストレージへ直送される。
//  どんなシールがあるかの一覧は StickerCatalog が持つ。
//
//  ★ 1.4 以前との違い ★
//    1.4 以前は「100pt 貯まるとランダムなシールが自動で出て、結果画面でボードに貼る」
//    仕組みだった。1.5 からポイントはエネルギーとして画面に表示し、
//    使い道（ガチャ／ショップ）を自分で選ぶ方式に変わった。
//
//  【3エリア管理】
//  ゲームモード（stickers）  : 全件保持・画面表示は先頭50枚のみ
//  ストレージ（storageEmojis）: 絵文字リストのみ・無制限
//  シール画面（playStickers） : 位置情報あり・上限100枚

// 絵文字シールの状態管理・永続化・ライフサイクル制御を担うシングルトン。

import SwiftUI

// MARK: - StickerStore

@Observable
final class StickerStore {

    // アプリ内どこからでも同一インスタンスにアクセスできるシングルトン
    static let shared = StickerStore()

    // MARK: - Sticker モデル

    // ボード上のシール1枚分のデータ。位置は画面サイズに依存しない比率で保持する。
    // Codable でシリアライズし、UserDefaults に JSON 形式で保存・復元する
    struct Sticker: Codable, Identifiable {
        var id: UUID = UUID()
        let emoji: String
        var xRatio: Double   // コンテナ幅に対する比率 (0.0–1.0)
        var yRatio: Double   // コンテナ高さに対する比率 (0.0–1.0)
        var scale:    Double = 1.0   // 表示倍率（シール画面のみ使用。1.0 = 40pt）
        var rotation: Double = 0     // 回転角（度。シール画面のみ使用）
    }

    // MARK: - 状態

    // ゲームモード用。全件保持するが StickerBoardView は prefix(50) のみ表示する
    private(set) var stickers: [Sticker] = []

    // ストレージ用。絵文字リストのみ・位置情報なし・無制限
    private(set) var storageEmojis: [String] = []

    // シール画面用。位置情報あり・上限 100 枚
    private(set) var playStickers: [Sticker] = []

    // MARK: - 上限定数

    private let gameDisplayLimit: Int    = 50    // ← 変更可：ゲームボードの表示上限
    private let playLimit:        Int    = 100   // ← 変更可：シール画面の上限

    // MARK: - 初期化

    // 外部からの直接初期化を禁止し、shared 経由のみを強制する
    private init() { load() }

    // MARK: - 公開API（獲得）

    /// 指定した絵文字を1枚、ストレージへ直接追加する。
    /// どうぶつめくりのように「自分で選んだシール」をそのまま渡す場面で使う。
    ///
    /// ★ ボードではなくストレージへ直送する理由 ★
    ///   ストレージには上限がないため、この経路は必ず成功する。
    ///   ボードが満杯かどうかの分岐そのものが不要になる。
    func addStickerToStorage(emoji: String) {
        addStickersToStorage([emoji])
    }

    /// 複数の絵文字をまとめてストレージへ直接追加する（ガチャ・ショップで手に入れたシール）。
    /// ストレージには上限がないため必ず成功する。保存は最後に1回だけ行う。
    func addStickersToStorage(_ emojis: [String]) {
        guard !emojis.isEmpty else { return }
        storageEmojis.append(contentsOf: emojis)
        saveStorage()   // 直後に落ちてもシールを失わないよう即保存する
    }

    // MARK: - 公開API（ゲームモード操作）

    /// ドラッグ終了後にゲームモードのシール位置を更新・保存する。
    func updatePosition(id: UUID, xRatio: Double, yRatio: Double) {
        guard let idx = stickers.firstIndex(where: { $0.id == id }) else { return }
        stickers[idx].xRatio = xRatio
        stickers[idx].yRatio = yRatio
        saveGame()
    }

    /// ドラッグ開始時にゲームモードのシールを最前面へ（配列末尾 = 最前面）。
    func bringToFront(id: UUID) {
        guard let idx = stickers.firstIndex(where: { $0.id == id }) else { return }
        let sticker = stickers.remove(at: idx)
        stickers.append(sticker)
        saveGame()
    }

    // MARK: - 公開API（ストレージ ↔ ゲームモード）

    /// ストレージ → ゲームモードへ1枚移動。満杯（50枚以上）のときは何もしない。
    /// - Returns: 移動成功なら true、満杯なら false
    @discardableResult
    func moveStorageToGame(emoji: String) -> Bool {
        guard stickers.count < gameDisplayLimit else { return false }
        if let idx = storageEmojis.firstIndex(of: emoji) {
            storageEmojis.remove(at: idx)
        }
        spawnSticker(emoji: emoji)
        saveStorage()
        return true
    }

    /// ゲームモード → ストレージへ1枚移動。常に成功する。
    func moveGameToStorage(id: UUID) {
        guard let idx = stickers.firstIndex(where: { $0.id == id }) else { return }
        let emoji = stickers[idx].emoji
        stickers.remove(at: idx)
        storageEmojis.append(emoji)
        saveGame()
        saveStorage()
    }

    // MARK: - 公開API（ストレージ ↔ シール画面）

    /// シール画面が満杯（100枚）かどうか。
    var isPlayFull: Bool { playStickers.count >= playLimit }

    /// ストレージ → シール画面へ1枚移動。満杯（100枚以上）のときは何もしない。
    /// 位置を指定しなければ螺旋状に自動配置する（トレイのタップ用）。
    /// - Returns: 移動成功なら true、満杯なら false
    @discardableResult
    func moveStorageToPlay(emoji: String, xRatio: Double? = nil, yRatio: Double? = nil) -> Bool {
        guard !isPlayFull else { return false }
        guard let idx = storageEmojis.firstIndex(of: emoji) else { return false }
        storageEmojis.remove(at: idx)
        if let x = xRatio, let y = yRatio {
            playStickers.append(Sticker(emoji: emoji, xRatio: x, yRatio: y))
            savePlay()
        } else {
            spawnPlaySticker(emoji: emoji)
        }
        saveStorage()
        return true
    }

    /// シール画面のシールをまとめてストレージへ戻す（「ぜんぶしまう」）。
    func moveAllPlayToStorage() {
        guard !playStickers.isEmpty else { return }
        storageEmojis.append(contentsOf: playStickers.map { $0.emoji })
        playStickers = []
        savePlay()
        saveStorage()
    }

    /// シール画面 → ストレージへ1枚移動。常に成功する。
    func movePlayToStorage(id: UUID) {
        guard let idx = playStickers.firstIndex(where: { $0.id == id }) else { return }
        let emoji = playStickers[idx].emoji
        playStickers.remove(at: idx)
        storageEmojis.append(emoji)
        savePlay()
        saveStorage()
    }

    // MARK: - 公開API（シール画面操作）

    /// ドラッグ終了後にシール画面のシール位置を更新・保存する。
    func updatePlayPosition(id: UUID, xRatio: Double, yRatio: Double) {
        guard let idx = playStickers.firstIndex(where: { $0.id == id }) else { return }
        playStickers[idx].xRatio = xRatio
        playStickers[idx].yRatio = yRatio
        savePlay()
    }

    /// ピンチ・回転・編集バー操作後にシール画面のシールの倍率と角度を更新・保存する。
    func updatePlayTransform(id: UUID, scale: Double, rotation: Double) {
        guard let idx = playStickers.firstIndex(where: { $0.id == id }) else { return }
        playStickers[idx].scale    = scale
        playStickers[idx].rotation = rotation
        savePlay()
    }

    /// ドラッグ開始時にシール画面のシールを最前面へ（配列末尾 = 最前面）。
    func bringPlayToFront(id: UUID) {
        guard let idx = playStickers.firstIndex(where: { $0.id == id }) else { return }
        let sticker = playStickers.remove(at: idx)
        playStickers.append(sticker)
        savePlay()
    }

    // MARK: - 公開API（リセット）

    /// 進捗リセット時に全データをまとめてクリアする。
    func reset() {
        stickers            = []
        storageEmojis       = []
        playStickers        = []
        UserDefaults.standard.removeObject(forKey: UDKey.stickers)
        UserDefaults.standard.removeObject(forKey: UDKey.storageEmojis)
        UserDefaults.standard.removeObject(forKey: UDKey.playStickers)
        UserDefaults.standard.removeObject(forKey: UDKey.pendingStickers)
    }

    // MARK: - 公開API（所有数）

    /// シールの種類ごとに、いま持っている枚数を数える（ショップの救済枠の抽選に使う）。
    /// MAKE10ボード・ストレージ・シール画面のどこにあっても1枚と数える。
    ///
    /// ★ 「これまでに手に入れた枚数」を別に記録していない理由 ★
    ///   シールを捨てる・消す方法はない（進捗リセットを除く）ため、
    ///   いま持っている枚数＝これまでに手に入れた枚数になる。
    ///   将来シールを消費する機能を作るときに、ここを初期値にして記録を始めればよい。
    func ownedCounts() -> [String: Int] {
        var counts: [String: Int] = [:]
        for s in stickers      { counts[s.emoji, default: 0] += 1 }
        for e in storageEmojis { counts[e,       default: 0] += 1 }
        for s in playStickers  { counts[s.emoji, default: 0] += 1 }
        return counts
    }

    // MARK: - 非公開

    /// ゲームボードへ螺旋状に自動配置する（ストレージからの移動時）。
    // 黄金角（約137.5°= 2.399rad）ベースの螺旋配置でシールを均等に散らばせる。
    // ボード下部（yRatio 0.83〜0.90）に収めるよう縦方向の振れ幅を 0.2 倍に抑えている
    private func spawnSticker(emoji: String) {
        let angle = Double(stickers.count) * 2.399
        let r     = 0.10 + Double(stickers.count % 4) * 0.04
        let x     = max(0.08, min(0.75, 0.42 + r * cos(angle)))
        let y     = max(0.83, min(0.90, 0.87 + r * sin(angle) * 0.2))
        stickers.append(Sticker(emoji: emoji, xRatio: x, yRatio: y))
        saveGame()
    }

    /// シール画面へ螺旋状に自動配置する（ストレージからの移動時）。
    // 全画面キャンバスを活かして中央から広がる螺旋配置にする
    private func spawnPlaySticker(emoji: String) {
        let angle = Double(playStickers.count) * 2.399
        let r     = 0.10 + Double(playStickers.count % 5) * 0.06
        let x     = max(0.08, min(0.92, 0.50 + r * cos(angle)))
        let y     = max(0.10, min(0.90, 0.50 + r * sin(angle)))
        playStickers.append(Sticker(emoji: emoji, xRatio: x, yRatio: y))
        savePlay()
    }

    // MARK: - 保存／読み込み

    private func saveGame() {
        guard let data = try? JSONEncoder().encode(stickers) else { return }
        UserDefaults.standard.set(data, forKey: UDKey.stickers)
    }

    private func saveStorage() {
        guard let data = try? JSONEncoder().encode(storageEmojis) else { return }
        UserDefaults.standard.set(data, forKey: UDKey.storageEmojis)
    }

    private func savePlay() {
        guard let data = try? JSONEncoder().encode(playStickers) else { return }
        UserDefaults.standard.set(data, forKey: UDKey.playStickers)
    }

    /// 起動時に UserDefaults から全状態を復元する。
    // 各配列のデコード失敗時は初期値（空配列）のままにする
    private func load() {
        if let data    = UserDefaults.standard.data(forKey: UDKey.stickers),
           let decoded = try? JSONDecoder().decode([Sticker].self, from: data) {
            stickers = decoded
        }
        if let data    = UserDefaults.standard.data(forKey: UDKey.storageEmojis),
           let decoded = try? JSONDecoder().decode([String].self, from: data) {
            storageEmojis = decoded
        }
        if let data    = UserDefaults.standard.data(forKey: UDKey.playStickers),
           let decoded = try? JSONDecoder().decode([Sticker].self, from: data) {
            playStickers = decoded
        }
        // ★ 配置待ちのシールをストレージへ移す理由 ★
        //   1.4 以前は、結果画面でボードに貼る前のシールを pendingStickers に保存していた。
        //   1.5 から手に入れたシールはストレージへ直送する方式になったため、
        //   起動時に残っていればストレージへ移し、どの画面からも扱えるようにする。
        if let data    = UserDefaults.standard.data(forKey: UDKey.pendingStickers),
           let decoded = try? JSONDecoder().decode([String].self, from: data),
           !decoded.isEmpty {
            storageEmojis.append(contentsOf: decoded)
            saveStorage()   // 先にストレージを保存してから配置待ちを消す（途中で落ちても失わない）
            UserDefaults.standard.removeObject(forKey: UDKey.pendingStickers)
        }
    }

    // MARK: - 表示用ヘルパー

    /// 絵文字1種類と、その枚数をまとめた表示用の値（ストレージ画面・シールトレイで共用）。
    struct EmojiGroup: Identifiable {
        let emoji: String
        let count: Int
        var id: String { emoji }  // 種類ごとに一意なので絵文字そのものを ID にする
    }

    /// フラットな絵文字配列を「初出順の [種類, 枚数]」へ集約する。
    /// 初出順を保つことで、枚数が増減しても並びが動かず操作感が安定する。
    static func grouped(_ emojis: [String]) -> [EmojiGroup] {
        var order:  [String] = []
        var counts: [String: Int] = [:]
        for e in emojis {
            if counts[e] == nil { order.append(e) }
            counts[e, default: 0] += 1
        }
        return order.map { EmojiGroup(emoji: $0, count: counts[$0]!) }
    }
}

// MARK: - Sticker の後方互換デコード

// ★ extension に置いている理由 ★
//   struct 本体に init(from:) を書くと memberwise init（Sticker(emoji:xRatio:yRatio:)）が
//   生成されなくなる。extension なら両方が使える。
// ★ decodeIfPresent が必要な理由 ★
//   scale / rotation は後から追加したキーで、既存ユーザーの UserDefaults には存在しない。
//   通常のデコードだとキー欠落で失敗し、起動時に全シールが消えてしまう。
extension StickerStore.Sticker {
    private enum CodingKeys: String, CodingKey {
        case id, emoji, xRatio, yRatio, scale, rotation
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id       = try c.decode(UUID.self,   forKey: .id)
        emoji    = try c.decode(String.self, forKey: .emoji)
        xRatio   = try c.decode(Double.self, forKey: .xRatio)
        yRatio   = try c.decode(Double.self, forKey: .yRatio)
        scale    = try c.decodeIfPresent(Double.self, forKey: .scale)    ?? 1.0
        rotation = try c.decodeIfPresent(Double.self, forKey: .rotation) ?? 0
    }
}
