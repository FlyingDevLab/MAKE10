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
//
//  ★ iCloud との同期 ★（CloudSyncManager.swift を参照）
//    ゲームモードとストレージのシールを1つの記録（"stickers"）にする。2台で食い違ったら、あとで変えたほうを残す。
//    シール帳に貼ったシールは、シール帳のページの記録（StickerBookStore）に入る。
//
//  ★ エネルギーへの交換（v1.6.0 から）★
//    つかっていないシール（ストレージ）は、1枚 30kcal のエネルギーに交換できる（シールじてんから）。
//    ゲーム画面やシール帳に貼ってあるシールは、作品をこわさないよう交換できない。
//    ある種類を交換して0枚になったら「これから でたら じどうで こうかん する？」と聞き、
//    はいなら、その種類はガチャで出たときに自動でエネルギーに変わる（autoExchange）。
//    自分で選んだシール（どうぶつめくりのごほうび）と、買ったシール（シールやさん）は自動で変えない。
//
//  ★ 「見つけた」記録（discovered）★
//    1.5 までは「1枚でも持っている＝見つけたことがある」としていた（シールが減らなかったため）。
//    交換で0枚にできるようになったので、一度でも手に入れた種類を別に覚えておき、
//    シールじてんは、こちらで「見つけた」かどうかを決める（0枚でも、黒いシルエットに戻らない）。

// 絵文字シールの状態管理・永続化・ライフサイクル制御を担うシングルトン。

import SwiftUI

// MARK: - ⚙️ 調整パラメータ

enum StickerExchangeTuning {
    /// シール1枚をエネルギーに交換したときの量（kcal）。
    /// ★ 30 にしている理由 ★ いちばん安い手に入れ方（10連ガチャ）でも1枚あたり約91kcal なので、
    ///   これより低ければ「買って交換すると得をする」抜け道はできない。
    static let kcalPerSticker: Double = 30   // ← 変更可（91 より小さくすること）
}

// MARK: - StickerStore

@Observable
final class StickerStore {

    // アプリ内どこからでも同一インスタンスにアクセスできるシングルトン
    static let shared = StickerStore()

    // MARK: - Sticker モデル

    // ボード上のシール1枚分のデータ。位置は画面サイズに依存しない比率で保持する。
    //
    // ★ なぜ座標を「比率」で保存するのか ★
    //   ピクセル座標のまま保存すると、別のサイズの端末（に機種変更した場合など）で
    //   シールが画面外に出てしまいます。コンテナのサイズに対する比率（0.0〜1.0）に
    //   変換しておけば、どの端末でも「画面のだいたい同じ場所」に復元できます。
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
    // ★ シール帳のシールは、開いているページの分（v1.6.0 から）★
    //   シール帳は12ページになった。全ページのシールは StickerBookStore が持っていて、
    //   ここでは「いま開いているページのシール」をそのまま読み書きする。
    //   ページを切り替えると、ここに見えるシールも切り替わる（StickerBookStore.openPage を参照）。
    private(set) var playStickers: [Sticker] {
        get { StickerBookStore.shared.currentStickers }
        set { StickerBookStore.shared.currentStickers = newValue }
    }

    /// 一度でも手に入れたことがある種類（シールじてんの「見つけた」。ファイル冒頭を参照）。
    private(set) var discovered: Set<String> = []

    /// ガチャで出たら自動でエネルギーに交換する種類（ファイル冒頭を参照）。
    private(set) var autoExchange: Set<String> = []

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
    /// - Parameter allowAutoExchange: true なら、自動交換にした種類はストレージに入れず、エネルギーに変える。
    ///   ランダムに出るガチャだけが true を渡す（自分で選んだ・買ったシールは変えない。ファイル冒頭を参照）。
    /// - Returns: 自動でエネルギーに変えたシール（出た順）。ガチャの結果画面で「エネルギーに かえたよ」と見せる
    @discardableResult
    func addStickersToStorage(_ emojis: [String], allowAutoExchange: Bool = false) -> [String] {
        guard !emojis.isEmpty else { return [] }
        let exchanged = allowAutoExchange ? emojis.filter { autoExchange.contains($0) } : []
        let kept      = allowAutoExchange ? emojis.filter { !autoExchange.contains($0) } : emojis
        markDiscovered(emojis)   // 自動で変えたシールも「見つけた」ことにする
        if !kept.isEmpty {
            storageEmojis.append(contentsOf: kept)
            saveStorage()   // 直後に落ちてもシールを失わないよう即保存する
        }
        if !exchanged.isEmpty {
            EnergyStore.shared.grantGift(StickerExchangeTuning.kcalPerSticker * Double(exchanged.count))
        }
        return exchanged
    }

    // MARK: - 公開API（エネルギーへの交換）

    /// その種類の、つかっていない枚数（ストレージにある枚数）。交換できるのはこの枚数まで。
    func unusedCount(of emoji: String) -> Int {
        storageEmojis.filter { $0 == emoji }.count
    }

    /// つかっていないシールの、ぜんぶの枚数。
    var unusedTotal: Int { storageEmojis.count }

    /// その種類を「見つけた」ことがあるか（シールじてんで色つきにするか）。
    func isDiscovered(_ emoji: String) -> Bool { discovered.contains(emoji) }

    /// つかっていないシールを1枚、エネルギーに交換する。
    /// - Returns: 増えたエネルギー（kcal）。つかっていないシールがなければ 0
    @discardableResult
    func exchangeOne(_ emoji: String) -> Double {
        // 後ろから探して消す（最近手に入れたほうから減らす）
        guard let index = storageEmojis.lastIndex(of: emoji) else { return 0 }
        storageEmojis.remove(at: index)
        saveStorage()   // シールを減らしてから
        let kcal = StickerExchangeTuning.kcalPerSticker
        EnergyStore.shared.grantGift(kcal)   // エネルギーを渡す（間で終了されても、子どもが損をしない順。StickerGacha.pull の逆）
        return kcal
    }

    /// つかっていないシールを、ぜんぶエネルギーに交換する。
    /// - Returns: 交換した枚数・増えたエネルギー・交換して0枚になった種類（自動交換を聞くのに使う）
    func exchangeAllUnused() -> (count: Int, kcal: Double, emptied: [String]) {
        let all = storageEmojis
        guard !all.isEmpty else { return (0, 0, []) }
        storageEmojis = []
        saveStorage()
        let kcal = StickerExchangeTuning.kcalPerSticker * Double(all.count)
        EnergyStore.shared.grantGift(kcal)
        let owned   = ownedCounts()
        var emptied: [String] = []
        for emoji in all where owned[emoji, default: 0] == 0 && !emptied.contains(emoji) && !autoExchange.contains(emoji) {
            emptied.append(emoji)
        }
        return (all.count, kcal, emptied)
    }

    /// その種類を、ゲーム画面・シール帳・ストレージのどこにも持っていないか（交換して0枚になったかを調べる）。
    func isEmpty(_ emoji: String) -> Bool { ownedCounts()[emoji, default: 0] == 0 }

    /// 自動交換のオン／オフ。
    func setAutoExchange(_ on: Bool, for emojis: [String]) {
        if on { autoExchange.formUnion(emojis) } else { autoExchange.subtract(emojis) }
        UserDefaults.standard.set(Array(autoExchange).sorted(), forKey: Self.autoExchangeKey)
        touch()
    }

    /// 手に入れた種類を「見つけた」に足す（足したものがあれば保存する）。
    private func markDiscovered(_ emojis: [String]) {
        let new = Set(emojis).subtracting(discovered)
        guard !new.isEmpty else { return }
        discovered.formUnion(new)
        UserDefaults.standard.set(Array(discovered).sorted(), forKey: Self.discoveredKey)
        touch()
    }

    private static let discoveredKey   = "stickerDiscovered"
    private static let autoExchangeKey = "stickerAutoExchange"

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
        playStickers = []   // 開いているページのシールだけをしまう（ほかのページはそのまま）
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
        StickerBookStore.shared.reset()   // シール帳の全ページ（シール・線・背景色）も消す
        UserDefaults.standard.removeObject(forKey: UDKey.stickers)
        UserDefaults.standard.removeObject(forKey: UDKey.storageEmojis)
        UserDefaults.standard.removeObject(forKey: UDKey.playStickers)
        UserDefaults.standard.removeObject(forKey: UDKey.pendingStickers)
        UserDefaults.standard.removeObject(forKey: Self.modifiedAtKey)
        discovered   = []
        autoExchange = []
        UserDefaults.standard.removeObject(forKey: Self.discoveredKey)
        UserDefaults.standard.removeObject(forKey: Self.autoExchangeKey)
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
        // シール帳は全ページを数える（開いていないページのシールも「もっている」）
        for (emoji, n) in StickerBookStore.shared.stickerCountsInAllPages() { counts[emoji, default: 0] += n }
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
        touch()
    }

    private func saveStorage() {
        guard let data = try? JSONEncoder().encode(storageEmojis) else { return }
        UserDefaults.standard.set(data, forKey: UDKey.storageEmojis)
        touch()
    }

    // MARK: - iCloud との同期

    /// シールを最後に変えた時刻を保存するキー（iCloud で2台の食い違いを比べるときに使う）。
    private static let modifiedAtKey = "stickersModifiedAt"
    private static let recordName    = "stickers"

    /// 最後に変えた時刻を今にして、iCloud に送る予定にする（iCloud を使っていなければ何も起きない）。
    private func touch() {
        UserDefaults.standard.set(Date(), forKey: Self.modifiedAtKey)
        CloudSyncManager.shared.markChanged(Self.recordName)
    }

    /// iCloud に送る中身。
    private struct CloudStickers: Codable {
        var game:    [Sticker]
        var storage: [String]
        /// 見つけた種類・自動交換の種類（1.6.0 の途中で足したので、それより前に送った記録では nil）
        var discovered:   [String]?
        var autoExchange: [String]?
    }

    private func savePlay() {
        // シール帳のシールは StickerBookStore が全ページまとめて保存する（1.5 までは UDKey.playStickers だった）
        StickerBookStore.shared.saveBook()
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
        // シール帳のシールは StickerBookStore が読み込む（1.5 のデータの引っ越しもそちらで行う）
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
        autoExchange = Set(UserDefaults.standard.stringArray(forKey: Self.autoExchangeKey) ?? [])
        if let saved = UserDefaults.standard.stringArray(forKey: Self.discoveredKey) {
            discovered = Set(saved)
        } else {
            // ★ はじめて（1.6.0 に更新した最初の起動）★
            //   まだ「見つけた」記録がないので、いま持っているシールから作る（1.5 までの「持っている＝見つけた」と同じ結果になる）。
            //   シール帳のシールも数えるため、StickerBookStore（全ページ）を読んだうえで数える。
            discovered = Set(ownedCounts().filter { $0.value > 0 }.keys)
            UserDefaults.standard.set(Array(discovered).sorted(), forKey: Self.discoveredKey)
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

// MARK: - iCloud との同期（CloudSyncSource）

extension StickerStore: CloudSyncSource {

    var cloudRecordNames: [String] { [Self.recordName] }

    func cloudPayload(for name: String) -> CloudPayload? {
        let payload = CloudStickers(game: stickers, storage: storageEmojis,
                                    discovered: Array(discovered).sorted(), autoExchange: Array(autoExchange).sorted())
        guard let data = try? JSONEncoder().encode(payload) else {
            return nil
        }
        let modifiedAt = UserDefaults.standard.object(forKey: Self.modifiedAtKey) as? Date ?? .distantPast
        return CloudPayload(data: data, modifiedAt: modifiedAt)
    }

    /// iCloud から届いたシールを反映する。あとで変えたほうを残す。
    /// 保存は UserDefaults に直接書く（saveGame / saveStorage は「変えた」扱いになり、送り返してしまうため）。
    func applyCloudPayload(_ payload: CloudPayload, for name: String, force: Bool) -> CloudApplyResult {
        guard let remote = try? JSONDecoder().decode(CloudStickers.self, from: payload.data) else { return .applied }
        let localDate = UserDefaults.standard.object(forKey: Self.modifiedAtKey) as? Date ?? .distantPast
        // 「見つけた」は、どちらの端末で見つけた種類も残す（足し合わせ）。減ることはない記録なので、新しさで選ばない
        let remoteDiscovered = Set(remote.discovered ?? [])
        if !force && localDate > payload.modifiedAt {
            let merged = discovered.union(remoteDiscovered)
            if merged != discovered {
                discovered = merged
                UserDefaults.standard.set(Array(merged).sorted(), forKey: Self.discoveredKey)
            }
            return .keptLocal   // この端末のほうがあとで変えた → この端末のシールを送り直す
        }
        stickers      = remote.game
        storageEmojis = remote.storage
        autoExchange  = Set(remote.autoExchange ?? [])
        // 「iCloud を もどす」（force）のときは iCloud の記録にそろえる。そうでなければ足し合わせる。
        // どちらでも、いま持っているシールは「見つけた」に入れる（古い記録で discovered が nil のときのため）
        let owned = Set(ownedCounts().filter { $0.value > 0 }.keys)
        discovered = (force ? remoteDiscovered : discovered.union(remoteDiscovered)).union(owned)
        UserDefaults.standard.set(try? JSONEncoder().encode(remote.game),    forKey: UDKey.stickers)
        UserDefaults.standard.set(try? JSONEncoder().encode(remote.storage), forKey: UDKey.storageEmojis)
        UserDefaults.standard.set(Array(autoExchange).sorted(), forKey: Self.autoExchangeKey)
        UserDefaults.standard.set(Array(discovered).sorted(),   forKey: Self.discoveredKey)
        UserDefaults.standard.set(payload.modifiedAt, forKey: Self.modifiedAtKey)
        return discovered == remoteDiscovered ? .applied : .keptLocal
    }

    /// シールを1枚でも持っていれば「遊んだ」とみなす（シール帳に貼った分は StickerBookStore が答える）。
    var hasLocalProgress: Bool { !stickers.isEmpty || !storageEmojis.isEmpty }
}
