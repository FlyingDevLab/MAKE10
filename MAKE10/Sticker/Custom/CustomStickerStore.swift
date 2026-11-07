//
//  CustomStickerStore.swift
//  FDL-TenBlitz
//
//  Created by 空飛ぶ研究室(FlyingDevLab) on 2026/11/07.
//
//  シールじてんをコンプリートすると作れる「オリジナルシール」の名簿と画像を持つシングルトン。
//  手描きの絵や、カメラで撮った写真にお絵かきしたものがシールになる。
//
//  役割分担:
//    - CustomStickerStore（このファイル）: オリジナルシールの作成・処分・保存・iCloud 同期
//    - StickerStore / StickerBookStore  : 手に入れたシールの保管（ふつうのシールと同じ場所に入る）
//    - StickerCatalog.pool              : ガチャ・シールやさんに出るシールの一覧（オリジナルも入る）
//    - StickerFace                      : シール1枚の表示（絵文字とオリジナルの違いを画面から隠す）
//    - CustomStickerMakerView           : シールを作る画面
//
//  ★ シールの ID は "custom:" で始まる文字列 ★
//    アプリのあちこちで、シールは絵文字の文字列（String）として持ち運ばれている。
//    オリジナルも "custom:<UUID>" という文字列にすれば、保管・ガチャ・シールやさん・交換の処理を
//    変えずに、そのまま通せる。画面に出すところだけ StickerFace で見分ける。
//
//  ★ 値段は「これまでに作った数」で決まる ★
//    1枚目 1,000 → 2枚目 2,000 → 3枚目 4,000 → 4枚目 8,000kcal と倍になり、5枚目からは 10,000kcal（ユーザーと決めた）。
//    川わたりの初回クリア報酬（1,000〜8,000）と同じ倍々の並び。
//    「いま持っている数」で数えると、処分して作り直せば安くなってしまうので、累計（createdTotal）で数える。
//
//  ★ 解放（コンプリート）は一度きりで残す ★
//    あとで絵文字を増やすと、コンプリートしていた人の じてんに空きができる。
//    それでシールづくりが使えなくならないよう、一度コンプリートしたら unlocked を立てたままにする。
//
//  ★ 処分すると、すべての場所から消える ★（ユーザーと決めた）
//    写真には顔が写っていることがあるので、処分したら確実に消せることを優先する。
//    じてん・ガチャ・シールやさん・持っている分・貼ってある分・iCloud のどこにも残さない。
//    端末の画像ファイルを消し、ID を disposed に残す。iCloud の記録も画像なしで上書きされる。
//    持っていた分は、貼ってあった分も含めてエネルギーに戻す（ユーザーと決めた）。量はふつうの交換と同じ。
//    シールを作ったときの値段は戻らない。戻すと、処分と作り直しで値段の意味がなくなるため。
//
//  ★ iCloud との同期 ★（CloudSyncManager.swift を参照）
//    全シールを画像ごと1つの記録（"customStickers"）にする。作成と処分のときしか変わらないので、
//    毎回まとめて送っても負担は小さい。処分した画像は、上書きで iCloud の記録からなくなる。
//    2台で食い違ったら、両方のシールを足し合わせ、どちらかで処分したシールは取り除く。
//    disposed を残しているのは、処分していない端末から届いた記録で、シールが生き返らないようにするため。

import SwiftUI
import UIKit

// MARK: - ⚙️ 調整パラメータ

enum CustomStickerTuning {
    /// 1枚目の値段（kcal）。1枚作るごとに倍になる。
    static let basePrice: Double = 1_000    // ← 変更可
    /// 値段の上限（kcal）。
    static let maxPrice:  Double = 10_000   // ← 変更可
    /// 保存する画像の1辺（px）。シール帳で大きくしても粗くならず、iCloud に送っても重すぎない大きさ。
    static let imageSide: CGFloat = 400     // ← 変更可
    /// シールの名前の長さの上限（文字）。
    static let maxNameLength = 12           // ← 変更可

    /// 次に作るシールの値段（kcal）。
    /// - Parameter createdTotal: これまでに作った数（処分した分も入れる）
    static func price(createdTotal: Int) -> Double {
        min(basePrice * pow(2, Double(max(createdTotal, 0))), maxPrice)
    }
}

// MARK: - CustomSticker

/// オリジナルシール1種類分（画像はファイルに分けて持つ）。
struct CustomSticker: Codable {
    /// "custom:<UUID>" の形。StickerStore などでは、これが絵文字の代わりになる。
    let id: String
    /// シールの名前。空なら画面では「オリジナル」と出す。
    let name: String
    let createdAt: Date
}

// MARK: - CustomStickerStore

// @Observable / シングルトンの解説は AppSettings.swift 冒頭を参照
@Observable
final class CustomStickerStore {

    static let shared = CustomStickerStore()

    // MARK: 状態

    /// 作ったシール（作った順）。
    private(set) var stickers: [CustomSticker] = []
    /// これまでに作った数。処分しても減らない（値段を決めるのに使う）。
    private(set) var createdTotal = 0
    /// 処分したシールの ID。iCloud でシールが生き返らないよう、ずっと残す（ファイル冒頭を参照）。
    private var disposed: Set<String> = []
    /// 一度でもコンプリートしたか（ファイル冒頭を参照）。
    private var unlocked = false

    /// 読み込んだ画像の置き場所。画面の描き直しのたびにファイルを読まないようにする。
    /// NSCache は、メモリが足りなくなると iOS が自動で中身を捨ててくれる（捨てても、また読めばよい）。
    @ObservationIgnored private let imageCache = NSCache<NSString, UIImage>()

    // MARK: 初期化

    private init() {
        load()
    }

    // MARK: 読み取り

    /// オリジナルシールの ID か。
    static func isCustom(_ id: String) -> Bool { id.hasPrefix(idPrefix) }

    /// 作ったシールの ID（作った順）。
    var ids: [String] { stickers.map(\.id) }

    /// シールづくりを使えるか。
    var isUnlocked: Bool { unlocked || isDexComplete }

    /// 次に作るシールの値段（kcal）。
    var nextPrice: Double { CustomStickerTuning.price(createdTotal: createdTotal) }

    /// 処分したシールか（iCloud から届いた記録に混ざっていたら取り除くのに使う）。
    func isDisposed(_ id: String) -> Bool { disposed.contains(id) }

    func sticker(for id: String) -> CustomSticker? { stickers.first { $0.id == id } }

    /// シールの画像。処分したシールや、まだ iCloud から届いていないシールは nil。
    func image(for id: String) -> UIImage? {
        guard sticker(for: id) != nil else { return nil }
        if let cached = imageCache.object(forKey: id as NSString) { return cached }
        guard let data = try? Data(contentsOf: Self.imageURL(for: id)),
              let image = UIImage(data: data) else { return nil }
        imageCache.setObject(image, forKey: id as NSString)
        return image
    }

    /// じてんのカテゴリがすべてそろったか。
    private var isDexComplete: Bool {
        let store = StickerStore.shared
        return StickerCatalog.all.allSatisfy { store.isDiscovered($0) }
    }

    /// コンプリートしていたら、解放を記録する（シールを手に入れたとき・じてんを開いたときに呼ぶ）。
    func recordUnlockIfComplete() {
        guard !unlocked, isDexComplete else { return }
        unlocked = true
        save()
        UserDefaults.standard.set(true, forKey: Self.completeNoticeKey)
    }

    /// 「コンプリート」のお知らせを、まだ見せていないか（タイトル画面でカードを出す）。
    /// iCloud では送らない。お知らせは、コンプリートした端末で1回出れば十分なので。
    var hasPendingCompleteNotice: Bool {
        UserDefaults.standard.bool(forKey: Self.completeNoticeKey)
    }

    /// お知らせを見せ終わったときに呼ぶ。
    func markCompleteNoticeShown() {
        UserDefaults.standard.removeObject(forKey: Self.completeNoticeKey)
    }

    private static let completeNoticeKey = "stickerCompleteNoticePending"

    // MARK: 作成

    /// シールを1枚作って、ストレージに1枚入れる。
    /// シールを渡してからエネルギーを減らす順の理由は StickerGacha.pull を参照。
    /// - Parameters:
    ///   - pngData: シールの画像（透過 PNG）
    ///   - name:    シールの名前
    /// - Returns: 作れたら true。作れないとき（画像を保存できなかったときなど）はエネルギーは減らない
    func create(pngData: Data, name: String) -> Bool {
        guard isUnlocked else { return false }
        let price  = nextPrice
        let energy = EnergyStore.shared
        guard energy.canAfford(price) else { return false }

        let id = Self.idPrefix + UUID().uuidString
        do {
            try Self.ensureFolder()
            try pngData.write(to: Self.imageURL(for: id), options: .atomic)
        } catch {
            print("CustomStickerStore: 画像の保存エラー: \(error.localizedDescription)")
            return false
        }
        let trimmed = String(name.trimmingCharacters(in: .whitespacesAndNewlines)
                                 .prefix(CustomStickerTuning.maxNameLength))
        stickers.append(CustomSticker(id: id, name: trimmed, createdAt: Date()))
        createdTotal += 1
        save()
        StickerStore.shared.addStickerToStorage(emoji: id)
        energy.spend(price)
        return true
    }

    // MARK: 処分

    /// シールを処分する。画像と、持っている分・貼ってある分をすべて消して、エネルギーに戻す（ファイル冒頭を参照）。
    /// - Returns: 増えたエネルギー（kcal）
    func dispose(_ id: String) -> Double {
        guard sticker(for: id) != nil else { return 0 }
        let kcal = disposalKcal(for: id)
        disposed.insert(id)
        stickers.removeAll { $0.id == id }
        removeImage(id)
        save()
        StickerStore.shared.purge([id])   // シールを減らしてから
        EnergyStore.shared.grantGift(kcal)   // エネルギーを渡す（順番の理由は StickerStore.exchangeOne を参照）
        return kcal
    }

    /// 処分したときに戻るエネルギー（kcal）。持っている全部の枚数ぶん。
    func disposalKcal(for id: String) -> Double {
        Double(StickerStore.shared.ownedCounts()[id, default: 0]) * StickerExchangeTuning.kcal(for: id)
    }

    // MARK: リセット

    /// 「さいしょから はじめる」で、端末のオリジナルシールをすべて消す（iCloud の分は残る）。
    func reset() {
        stickers     = []
        createdTotal = 0
        disposed     = []
        unlocked     = false
        imageCache.removeAllObjects()
        markCompleteNoticeShown()
        try? FileManager.default.removeItem(at: Self.folderURL)
    }

    // MARK: 保存／読み込み

    /// 端末に保存する中身（画像は別のファイル）。
    private struct Index: Codable {
        var stickers:     [CustomSticker]
        var createdTotal: Int
        var disposed:     [String]
        var unlocked:     Bool
    }

    private var currentIndex: Index {
        Index(stickers: stickers, createdTotal: createdTotal, disposed: disposed.sorted(), unlocked: unlocked)
    }

    private func save() {
        writeIndex()
        CloudSyncManager.shared.markChanged(Self.recordName)   // iCloud を使っていなければ何も起きない
    }

    /// 端末に書くだけ（iCloud から届いた記録を書くときは、こちらを使う。送り返さないため）。
    private func writeIndex() {
        do {
            try Self.ensureFolder()
            try JSONEncoder().encode(currentIndex).write(to: Self.indexURL, options: .atomic)
        } catch {
            print("CustomStickerStore: 保存エラー: \(error.localizedDescription)")
        }
    }

    private func load() {
        guard let data  = try? Data(contentsOf: Self.indexURL),
              let index = try? JSONDecoder().decode(Index.self, from: data) else { return }
        stickers     = index.stickers
        createdTotal = index.createdTotal
        disposed     = Set(index.disposed)
        unlocked     = index.unlocked
    }

    private func removeImage(_ id: String) {
        imageCache.removeObject(forKey: id as NSString)
        try? FileManager.default.removeItem(at: Self.imageURL(for: id))
    }

    // MARK: 保存先

    private static let idPrefix = "custom:"

    /// Documents/CustomStickers/
    private static var folderURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("CustomStickers", isDirectory: true)
    }

    /// Documents/CustomStickers/index.json
    private static var indexURL: URL { folderURL.appendingPathComponent("index.json") }

    /// Documents/CustomStickers/<UUID>.png
    private static func imageURL(for id: String) -> URL {
        folderURL.appendingPathComponent(id.dropFirst(idPrefix.count) + ".png")
    }

    private static func ensureFolder() throws {
        try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
    }

    fileprivate static let recordName = "customStickers"
}

// MARK: - iCloud との同期（CloudSyncSource）

extension CustomStickerStore: CloudSyncSource {

    /// iCloud に送る中身。画像も入れる（1つの記録にまとめる理由はファイル冒頭を参照）。
    /// ★ バイナリの plist にする理由 ★
    ///   JSON だと Data が base64 の文字になり、3割ほど大きくなって読み書きも遅い。
    private struct CloudRecord: Codable {
        var index:  Index
        /// シールの ID → PNG
        var images: [String: Data]
    }

    var cloudRecordNames: [String] { [Self.recordName] }

    func cloudPayload(for name: String) -> CloudPayload? {
        var record = CloudRecord(index: currentIndex, images: [:])
        for sticker in stickers {
            record.images[sticker.id] = try? Data(contentsOf: Self.imageURL(for: sticker.id))
        }
        // 画像が読めないシールは、名簿にも入れない
        record.index.stickers.removeAll { record.images[$0.id] == nil }

        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        guard let data = try? encoder.encode(record) else { return nil }
        // 足し合わせて合わせるので、時刻は比べない（.distantPast でよい）
        return CloudPayload(data: data, modifiedAt: .distantPast)
    }

    /// iCloud から届いたシールを合わせる。
    /// 「足し合わせ」なので、片方の端末で作ったシールが消えることはない。処分だけは両方に広げる。
    /// force（「iCloud を もどす」）のときは iCloud の記録にそろえる。
    func applyCloudPayload(_ payload: CloudPayload, for name: String, force: Bool) -> CloudApplyResult {
        guard let record = try? PropertyListDecoder().decode(CloudRecord.self, from: payload.data) else { return .applied }
        let remote = record.index

        let allDisposed = disposed.union(remote.disposed)
        var merged = force ? [] : stickers
        for sticker in remote.stickers where !merged.contains(where: { $0.id == sticker.id }) {
            merged.append(sticker)
        }
        merged.removeAll { allDisposed.contains($0.id) }
        merged.sort { $0.createdAt < $1.createdAt }

        // 届いた画像のうち、まだないものをファイルに書く（作ったあとで画像が変わることはない）
        try? Self.ensureFolder()
        let kept = Set(merged.map(\.id))
        for (id, png) in record.images where kept.contains(id) {
            let url = Self.imageURL(for: id)
            if !FileManager.default.fileExists(atPath: url.path) {
                try? png.write(to: url, options: .atomic)
            }
        }

        // 消えることになったシールは、画像も、持っている分・貼ってある分も消す
        let removed = Set(stickers.map(\.id)).subtracting(kept)
        for id in removed { removeImage(id) }
        // 新しく処分を知ったシールも取り除く。処分より先に届いた「持っているシール」の記録に、
        // まだ入っているかもしれないため（届く順番は決まっていない）
        let purged = removed.union(allDisposed.subtracting(disposed))

        stickers     = merged
        disposed     = allDisposed
        createdTotal = force ? remote.createdTotal : max(createdTotal, remote.createdTotal, merged.count)
        unlocked     = force ? remote.unlocked     : unlocked || remote.unlocked
        writeIndex()
        StickerStore.shared.purge(purged)

        let sameAsRemote = kept == Set(remote.stickers.map(\.id))
            && allDisposed == Set(remote.disposed)
            && createdTotal == remote.createdTotal
            && unlocked == remote.unlocked
        return sameAsRemote ? .applied : .keptLocal
    }

    /// シールを1枚でも作っていれば「遊んだ」とみなす。
    var hasLocalProgress: Bool { !stickers.isEmpty }
}
