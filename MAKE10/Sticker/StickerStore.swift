//
//  StickerStore.swift
//  FDL-TenBlitz
//
//  Created by 空飛ぶ研究室(FlyingDevLab) on 2026/03/21.
//
//  約100ポイント獲得ごとに絵文字シールを1つ獲得。
//  ポイントは難易度・モードに応じて変動（1.1pt〜2.6pt/問）するため
//  実際の問題数は難易度によって異なる。
//
//  【3エリア管理】
//  ゲームモード（stickers）  : 全件保持・画面表示は先頭50枚のみ
//  ストレージ（storageEmojis）: 絵文字リストのみ・無制限
//  シール画面（playStickers） : 位置情報あり・上限100枚

// 絵文字シールの状態管理・永続化・ライフサイクル制御を担うシングルトン。
// ポイント蓄積 → pending（またはストレージ直送）→ ボード配置という流れで管理する。
// ゲームボードが満杯（50枚以上）のときは新規シールをストレージへ直接送出する。

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
    }

    // MARK: - 状態

    // ゲームモード用。全件保持するが StickerBoardView は prefix(50) のみ表示する
    private(set) var stickers: [Sticker] = []

    // ストレージ用。絵文字リストのみ・位置情報なし・無制限
    private(set) var storageEmojis: [String] = []

    // シール画面用。位置情報あり・上限 100 枚
    private(set) var playStickers: [Sticker] = []

    // リザルト画面でゲームボードへ配置するシール一時保持用
    private(set) var pendingStickers: [String] = []

    // リザルト画面でストレージへ送出されたシール枚数。
    // FinishedView がメッセージ表示の判断に使う。表示後に clearPendingStorage() でリセットする
    private(set) var pendingStorageCount: Int = 0

    // 累積ポイント。nextMilestone（100pt）に達するたびに 0 にリセットしてシールを1枚発行する
    private(set) var totalCorrect: Double = 0

    // MARK: - 上限定数

    private let gameDisplayLimit: Int    = 50    // ← 変更可：ゲームボードの表示上限
    private let playLimit:        Int    = 100   // ← 変更可：シール画面の上限
    private let nextMilestone:    Double = 100.0 // ← 変更可：シール獲得に必要なポイント

    // MARK: - 絵文字プール（ランダムに1つ選ばれる）
    // 🌸 が複数・☁️ が3つなど出現確率に重みを持たせている（多いほど出やすい）
    private static let palette: [String] = [
        "😄","🥹","☺️","😊","😋",
        "🦁","🐧","🦊","🌊",
        "🌟","🌈","🦋","🌷","🌹","🌼","🌻","🌸","🌸","🌸","🍀","🦄","🐠","🎈","🎀",
        "🌺","🐬","🌙","☀️","🍭","🎠","🌴",
        "🎵","🍕","🍦","🦖","🦔","🎪","🌻","🍄",
        "🐣","🦩","🎡","🎋","🎍","🌏","🪄","🏆",
        "🚗","🚒","🚐","🚑","🚓","🏎️","🚕","🛩️","🚀",
        "☁️","☁️","☁️","🏠","💩"
    ]

    // MARK: - 初期化

    // 外部からの直接初期化を禁止し、shared 経由のみを強制する
    private init() { load() }

    // MARK: - 公開API（獲得・pending 管理）

    /// 正解時に呼ぶ。ゲームボードが満杯なら新規シールをストレージへ直接送出する。
    /// points は難易度・モードに応じて変動（例：Blitz 正解=2.6pt、通常正解=1.1pt）。
    func recordCorrect(points: Double = 1.0) {
        totalCorrect += points
        UserDefaults.standard.set(totalCorrect, forKey: UDKey.totalCorrectAllTime)
        guard totalCorrect >= nextMilestone else { return }

        let emoji = Self.palette.randomElement()!
        totalCorrect = 0
        UserDefaults.standard.set(0, forKey: UDKey.totalCorrectAllTime)

        if stickers.count >= gameDisplayLimit {
            // ゲームボード満杯 → ストレージへ直接送出
            storageEmojis.append(emoji)
            pendingStorageCount += 1
            saveStorage()
        } else {
            // 通常ルート → リザルト画面のバナーに表示してから配置
            pendingStickers.append(emoji)
        }
    }

    /// 全問正解ボーナスなど、ポイント外でシールを1枚追加する。
    // EmojiQuizViewModel の advance() から pct == 1.0 のときに呼ばれる
    func addBonusSticker() {
        let emoji = Self.palette.randomElement()!
        if stickers.count >= gameDisplayLimit {
            storageEmojis.append(emoji)
            pendingStorageCount += 1
            saveStorage()
        } else {
            pendingStickers.append(emoji)
        }
    }

    /// リザルト画面での表示完了後に呼ぶ。ストレージ送出カウントをリセットする。
    func clearPendingStorage() {
        pendingStorageCount = 0
    }

    /// リザルト画面でユーザーが絵文字をドラッグして配置したときに呼ぶ。
    // firstIndex(of:) で同じ絵文字が複数あっても先頭の1つだけを消費する
    func placePendingSticker(emoji: String, xRatio: Double, yRatio: Double) {
        if let idx = pendingStickers.firstIndex(of: emoji) {
            pendingStickers.remove(at: idx)
        }
        stickers.append(Sticker(emoji: emoji, xRatio: xRatio, yRatio: yRatio))
        saveGame()
    }

    /// ドラッグ配置されなかった残りの pending を自動配置するフォールバック。
    // リザルト画面の onDisappear やボタン操作時に呼ばれる
    func confirmPendingStickers() {
        let toAdd = pendingStickers
        pendingStickers = []
        for emoji in toAdd { spawnSticker(emoji: emoji) }
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

    /// ストレージ → シール画面へ1枚移動。満杯（100枚以上）のときは何もしない。
    /// - Returns: 移動成功なら true、満杯なら false
    @discardableResult
    func moveStorageToPlay(emoji: String) -> Bool {
        guard playStickers.count < playLimit else { return false }
        if let idx = storageEmojis.firstIndex(of: emoji) {
            storageEmojis.remove(at: idx)
        }
        spawnPlaySticker(emoji: emoji)
        saveStorage()
        return true
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
        totalCorrect        = 0
        pendingStickers     = []
        pendingStorageCount = 0
        UserDefaults.standard.removeObject(forKey: UDKey.stickers)
        UserDefaults.standard.removeObject(forKey: UDKey.storageEmojis)
        UserDefaults.standard.removeObject(forKey: UDKey.playStickers)
        UserDefaults.standard.removeObject(forKey: UDKey.totalCorrectAllTime)
    }

    // MARK: - 非公開

    /// ゲームボードへ螺旋状に自動配置する（pending フォールバック・ストレージ移動時）。
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
        totalCorrect = UserDefaults.standard.double(forKey: UDKey.totalCorrectAllTime)

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
    }
}
