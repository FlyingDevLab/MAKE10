//
//  StickerStore.swift
//  FDL-TenBlitz
//
//  Created by 空飛ぶ研究室(FlyingDevLab) on 2026/03/21.
//
//  約100ポイント獲得ごとに絵文字シールを1つ獲得。
//  ポイントは難易度・モードに応じて変動（1.1pt〜2.6pt/問）するため
//  実際の問題数は難易度によって異なる。
//  シールの位置はUserDefaultsに保存され、次回起動後も保持される。
//  7個以降はゴミ箱機能が解放され、ドラッグで削除できる。

// 絵文字シールの状態管理・永続化・ライフサイクル制御を担うシングルトン。
// ポイント蓄積 → pendingStickers → ボード配置という3段階の流れで
// シールの獲得からボード反映までを管理する。

import SwiftUI

// MARK: - Sticker Store

@Observable
final class StickerStore {

    // アプリ内どこからでも同一インスタンスにアクセスできるシングルトン
    static let shared = StickerStore()

    // MARK: - Sticker Model

    // ボード上のシール1枚分のデータ。位置は画面サイズに依存しない比率で保持する。
    // Codableでシリアライズし、UserDefaultsにJSON形式で保存・復元する
    struct Sticker: Codable, Identifiable {
        var id: UUID = UUID()
        let emoji: String
        var xRatio: Double   // コンテナ幅に対する比率 (0.0–1.0)
        var yRatio: Double   // コンテナ高さに対する比率 (0.0–1.0)
    }

    // MARK: - State

    // ボード上に配置済みのシール一覧。外部からの直接変更はpublic APIを通じて行う
    private(set) var stickers: [Sticker] = []

    // 累積ポイント。nextMilestone（100pt）を超えるたびに0にリセットしてシールを1枚発行する
    private(set) var totalCorrect: Double = 0

    /// ゲーム終了時のリザルト画面で表示・確定するシール群（まだボードには追加されていない）
    // リザルト画面がこの配列を読み取ってバナーに表示し、ドラッグ or 自動配置でボードに移す
    private(set) var pendingStickers: [String] = []

    /// 7個以上になったら解放。一度解放したら進捗リセット以外で消えない。
    // didSetでUserDefaultsに即時保存し、次回起動後も解放状態を維持する
    private(set) var isTrashUnlocked: Bool = false {
        didSet { UserDefaults.standard.set(isTrashUnlocked, forKey: UDKey.isTrashUnlocked) }
    }

    // ポイントがこの値に達したらシールを1枚発行する閾値
    private let nextMilestone: Double = 100.0

    // MARK: - シールの絵文字プール（ランダムに1つ選ばれる）
    // 🌸が複数・☁️が3つなど出現確率に重みを持たせている（多いほど出やすい）
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

    // MARK: - Init

    // 外部からの直接初期化を禁止し、shared経由のみを強制する。
    // 起動時にUserDefaultsからシール・ポイント・ゴミ箱状態を復元する
    private init() { load() }

    // MARK: - Public API

    /// 正解時に呼ぶ。累積ポイントが nextMilestone（100pt）に達したら pendingSticker にセットする。
    /// 実際のボード追加はリザルト画面の confirmPendingSticker() で行う。
    /// points は難易度・モードに応じて変動（例：Blitz正解=2.6pt、通常正解=1.1pt）。
    func recordCorrect(points: Double = 1.0) {
        totalCorrect += points
        UserDefaults.standard.set(totalCorrect, forKey: UDKey.totalCorrectAllTime)
        if totalCorrect >= nextMilestone {
            let emoji = Self.palette.randomElement()!
            // ポイントをリセットし、次のシール獲得に向けてカウントを再スタートする
            totalCorrect = 0
            UserDefaults.standard.set(0, forKey: UDKey.totalCorrectAllTime)
            pendingStickers.append(emoji)   // リザルト画面が引き取るまで保持
        }
    }

    /// 全問正解ボーナスなど、ポイント外でステッカーを1枚追加する。
    // EmojiQuizViewModelのadvance()からpct == 1.0のときに呼ばれる
    func addBonusSticker() {
        pendingStickers.append(Self.palette.randomElement()!)
    }

    /// リザルト画面の onAppear で呼ぶ。pending を全て正式にボードへ追加する。
    /// ドラッグ配置されなかった残りのシールをデフォルト位置に一括追加するフォールバック用。
    // spawnSticker()が螺旋状の座標計算でボード下部に分散配置する
    func confirmPendingStickers() {
        let toAdd = pendingStickers
        pendingStickers = []
        for emoji in toAdd { spawnSticker(emoji: emoji) }
    }

    /// リザルト画面でユーザーが絵文字を直接ドラッグして配置したときに呼ぶ。
    /// pendingStickers から該当絵文字を1つ消費してボードへ追加する。
    // firstIndex(of:)で同じ絵文字が複数あっても先頭の1つだけを消費する
    func placePendingSticker(emoji: String, xRatio: Double, yRatio: Double) {
        if let idx = pendingStickers.firstIndex(of: emoji) {
            pendingStickers.remove(at: idx)
        }
        stickers.append(Sticker(emoji: emoji, xRatio: xRatio, yRatio: yRatio))
        // 配置後に7枚以上になったらゴミ箱を解放する
        if stickers.count >= 7 { isTrashUnlocked = true }
        save()
    }

    /// ドラッグ終了後に位置を更新・保存する。
    // idで対象シールを特定し、比率座標を更新してUserDefaultsに永続化する
    func updatePosition(id: UUID, xRatio: Double, yRatio: Double) {
        guard let idx = stickers.firstIndex(where: { $0.id == id }) else { return }
        stickers[idx].xRatio = xRatio
        stickers[idx].yRatio = yRatio
        save()
    }

    /// ドラッグ開始時に最前面に持ってくる（配列末尾 = 最前面）
    // ZStackはインデックス順に重なるため、配列末尾のシールが画面最前面に表示される
    func bringToFront(id: UUID) {
        guard let idx = stickers.firstIndex(where: { $0.id == id }) else { return }
        let sticker = stickers.remove(at: idx)
        stickers.append(sticker)
        save()
    }

    /// ゴミ箱にドロップしてシールを削除する。
    func deleteSticker(id: UUID) {
        stickers.removeAll { $0.id == id }
        save()
    }

    /// ゴミ箱の長押しで全シールをまとめて削除する。
    /// 進捗（totalCorrect）とゴミ箱解放状態（isTrashUnlocked）は保持する。
    // シールをすべて消してもゴミ箱の解放状態は維持するのがresetとの違い
    func deleteAllStickers() {
        stickers = []
        save()
    }

    /// 進捗リセット時にシールもまとめてクリアする。
    // deleteAllStickersと違い、totalCorrectとisTrashUnlockedも含めて完全にリセットする
    func reset() {
        stickers = []
        totalCorrect = 0
        isTrashUnlocked = false
        pendingStickers = []
        // UserDefaultsのデータもまとめて削除し、次回起動時の誤復元を防ぐ
        UserDefaults.standard.removeObject(forKey: UDKey.stickers)
        UserDefaults.standard.removeObject(forKey: UDKey.totalCorrectAllTime)
        UserDefaults.standard.removeObject(forKey: UDKey.isTrashUnlocked)
    }

    // MARK: - Private

    // confirmPendingStickers()のフォールバック配置で使われる座標計算メソッド。
    // 黄金角（約137.5°= 2.399rad）ベースの螺旋配置でシールを均等に散らばせる。
    // ボード下部（yRatio 0.83〜0.90）に収めるよう縦方向の振れ幅を0.2倍に抑えている
    private func spawnSticker(emoji: String) {
        let angle = Double(stickers.count) * 2.399  // 黄金角ベースで螺旋状に分散させる
        let r = 0.10 + Double(stickers.count % 4) * 0.04  // 半径を0〜3枚周期で少しずつ広げる
        let x = max(0.08, min(0.75, 0.42 + r * cos(angle)))
        let y = max(0.83, min(0.90, 0.87 + r * sin(angle) * 0.2))

        stickers.append(Sticker(emoji: emoji, xRatio: x, yRatio: y))
        // 自動配置でも7枚以上になったらゴミ箱を解放する
        if stickers.count >= 7 { isTrashUnlocked = true }
        save()
    }

    // stickers配列をJSONエンコードしてUserDefaultsに保存する。
    // エンコード失敗時は何もせずリターンし、既存データを上書きしない
    private func save() {
        guard let data = try? JSONEncoder().encode(stickers) else { return }
        UserDefaults.standard.set(data, forKey: UDKey.stickers)
    }

    // 起動時にUserDefaultsから全状態を復元する。
    // stickersのデコード失敗時はreturnして初期値（空配列）のままにする
    private func load() {
        totalCorrect    = UserDefaults.standard.double(forKey: UDKey.totalCorrectAllTime)
        isTrashUnlocked = UserDefaults.standard.bool(forKey: UDKey.isTrashUnlocked)
        guard
            let data = UserDefaults.standard.data(forKey: UDKey.stickers),
            let decoded = try? JSONDecoder().decode([Sticker].self, from: data)
        else { return }
        stickers = decoded
    }
}
