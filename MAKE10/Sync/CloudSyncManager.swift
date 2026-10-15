//
//  CloudSyncManager.swift
//  FDL-TenBlitz
//
//  Created by 空飛ぶ研究室(FlyingDevLab) on 2026/10/15.
//
//  アプリの記録（シール帳の絵・シール・エネルギー・ハイスコアなど）を、利用者本人の iCloud に保存して、
//  機種変更やアプリの入れ直しのあとでも戻せるようにし、同じ Apple アカウントの端末どうしでそろえる係。
//
//  役割分担:
//    - CloudSyncManager（このファイル）: iCloud とのやりとり（送る・受け取る・食い違いの処理・2択の保留）
//    - CloudSyncSource（このファイルの約束ごと）: 各記録の持ち主（StickerBookStore など）が守る約束。
//        「自分の記録を iCloud 用のデータにして渡す」「iCloud から届いたデータを自分に反映する」
//    - 各ストア: 記録が変わったら markChanged(_:) で知らせる
//    - SettingsView: 「iCloud に ほぞん」のオン／オフ、2択の画面
//
//  ★ どこに保存されるのか ★
//    利用者本人の iCloud の「プライベートデータベース」。本人の Apple アカウントでしか読めず、
//    開発者（Flying Dev Lab）を含め、ほかの人は見られない。外部の会社へも送らない。
//    iCloud にサインインしていない・オフにしている端末では、今までどおり端末の中だけに保存する。
//
//  ★ CKSyncEngine とは？ ★
//    Apple が用意している「端末と iCloud の記録をそろえる」仕組み（iOS 17 から）。
//    いつ送るか・いつ受け取るか・電波がないときに待つ、といった面倒なことを代わりにやってくれる。
//    こちらは「送りたい記録の名前を伝える」「頼まれたら記録を作って渡す」「届いた記録を反映する」だけを書く。
//
//  ★ 記録の単位 ★
//    「記録の名前」（例: "page-01"、"energy"）ごとに1つのまとまり（CKRecord）にする。
//    中身はどれも Data（各ストアが JSON などにしたもの）と、最後に変えた時刻。
//    大きいデータ（お絵かきの線・かべがみの画像）は、添付ファイル（CKAsset）として送る。
//
//  ★ 2台で食い違ったとき ★
//    どちらを残すかは、記録の持ち主が決める（applyCloudPayload の戻り値）。
//    多くは「あとで変えたほう」、ハイスコアは「大きいほう」など、記録ごとにふさわしい決め方が違うため。
//
//  ★ はじめてつなぐとき・オンに戻したときの2択 ★（ユーザーと決めたルール）
//    iCloud にも端末にも記録があるときは、勝手に混ぜたり消したりせず、保護者に選んでもらう。
//      「iCloud の記録を この端末に もどす」/「この端末の記録で iCloud を うわがきする」
//    まだ遊んでいない新しい端末なら、聞かずに iCloud の記録を受け取る（機種変更が自然に戻る）。
//
//  ★「さいしょから はじめる」のとき ★（ユーザーと決めたルール）
//    iCloud の分は残す。そのため、リセットの前に、この端末の同期をオフにする（disableForReset）。
//    オフにしないと、空になった記録が iCloud に上書きされてしまう。
//
//  ⚠️ iCloud（CloudKit）の機能が Xcode で有効になっていないと、iCloud につなぐ処理でアプリが落ちる。
//    有効にするまでは isCloudKitConfigured を false のままにしておくこと（下の「⚙️ 調整パラメータ」を参照）。

import CloudKit
import Foundation
import UIKit

// MARK: - 記録を iCloud とやりとりするための約束ごと

/// iCloud とやりとりする記録1つ分の中身。
struct CloudPayload {
    /// 記録の中身（各ストアが JSON などにしたもの）
    var data: Data
    /// 最後に変えた時刻（「あとで変えたほうを残す」ときに比べる）
    var modifiedAt: Date
}

/// iCloud から届いた記録を反映した結果。
enum CloudApplyResult {
    /// iCloud の記録を受け取った（または合わせた結果が iCloud と同じになった）
    case applied
    /// 端末の記録のほうを残した（または合わせた結果が iCloud と違う）。iCloud へ送り直す
    case keptLocal
}

/// 記録の持ち主（StickerBookStore・EnergyStore など）が守る約束。
protocol CloudSyncSource: AnyObject {
    /// この持ち主が受け持つ記録の名前（例: ["page-01", ..., "page-12"]）。アプリ全体で重ならないこと。
    var cloudRecordNames: [String] { get }

    /// 記録を iCloud に送るデータにして返す。送るものがなければ nil。
    func cloudPayload(for name: String) -> CloudPayload?

    /// iCloud から届いた記録を反映する。
    /// - Parameter force: true なら比べずに iCloud の記録で置きかえる（2択で「iCloud を もどす」を選んだとき）
    func applyCloudPayload(_ payload: CloudPayload, for name: String, force: Bool) -> CloudApplyResult

    /// この端末で、もう遊んだ記録があるか（はじめてつなぐときの2択を出すかどうかに使う）。
    var hasLocalProgress: Bool { get }
}

// MARK: - 保存のキー

extension UDKey {
    /// iCloud に ほぞん（同期）するか。保護者が設定でオン／オフする。まだ決めていなければオン
    static let iCloudSyncOn          = "iCloudSyncOn"
    /// 次に iCloud から受け取ったとき、2択が要るか調べるか（はじめてつなぐとき・オンに戻したとき）
    static let iCloudNeedsFirstCheck = "iCloudNeedsFirstCheck"
    /// 2択を出す理由（0 = はじめてつなぐ、1 = オンに戻した）
    static let iCloudCheckReason     = "iCloudCheckReason"
    /// 2択で「この端末の記録で うわがき」を選び、まだ送り終わっていないか
    static let iCloudForceUpload     = "iCloudForceUpload"
    /// 最後に iCloud とそろえた時刻
    static let iCloudLastSync        = "iCloudLastSync"
}

// MARK: - CloudSyncManager

// @Observable / シングルトンの解説は AppSettings.swift 冒頭を参照
@Observable
final class CloudSyncManager {

    static let shared = CloudSyncManager()

    // MARK: ⚙️ 調整パラメータ

    /// Xcode で iCloud（CloudKit）の機能を有効にしたか（2026-10-15 に Debug・Release とも有効にした）。
    /// ⚠️ 変更注意: 有効にしていないのに true にすると、iCloud につなぐ処理でアプリが落ちる。
    static let isCloudKitConfigured = true
    /// iCloud のコンテナの名前。Xcode の「Signing & Capabilities」で作る名前と同じにすること。
    static let containerID = "iCloud.com.flyingdevlab.FDL-TenBlitz"
    /// 記録を入れる区画（ゾーン）の名前。
    static let zoneID = CKRecordZone.ID(zoneName: "AppData")
    /// 記録の種類の名前（CloudKit Console に、この名前で出る）。
    static let recordType = "AppData"
    /// この大きさ（バイト）を超えるデータは、添付ファイル（CKAsset）で送る。← 変更可
    /// （1つの記録に入れられるのは全部で 1MB までなので、大きいものは添付にする）
    static let assetThreshold = 100_000

    // MARK: 状態（設定画面に出す）

    /// いまの様子。
    enum Status: Equatable {
        case off              // オフにしている（または iCloud の機能がまだない）
        case noAccount        // iCloud にサインインしていない
        case syncing          // やりとりしている
        case idle             // そろっている
        case failed(String)   // うまくいかなかった（理由）
    }
    private(set) var status: Status = .off

    /// 2択を出す理由。
    enum ChoiceReason: Int {
        case firstConnection = 0   // はじめてつなぐ
        case reenabled       = 1   // オンに戻した
    }

    /// 2択の画面を出すか（iCloud にも端末にも記録があって、保護者に選んでもらう必要がある）。
    private(set) var needsChoice = false
    /// 2択を出す理由（画面の文に使う）。
    private(set) var choiceReason: ChoiceReason = .firstConnection

    /// 最後に iCloud とそろえた時刻。
    private(set) var lastSyncDate: Date?

    /// iCloud に ほぞんするか（保護者の設定）。
    private(set) var isEnabled: Bool

    // MARK: 内部の状態

    /// 記録の名前 → 持ち主
    private var sources: [String: CloudSyncSource] = [:]
    private var engine: CKSyncEngine?
    private var container: CKContainer?

    /// iCloud から届いた記録を反映している間 true。この間に持ち主が markChanged を呼んでも送り返さない。
    private var isApplyingRemote = false
    /// 2択を待っている間、iCloud から届いた記録をここに置いておく（まだ反映しない）。
    private var heldRemote: [String: CloudPayload] = [:]

    // MARK: 初期化

    private init() {
        let defaults = UserDefaults.standard
        // まだ決めていなければオン（機種変更で戻すためには、はじめからオンでないと意味がない）
        isEnabled    = defaults.object(forKey: UDKey.iCloudSyncOn) as? Bool ?? true
        lastSyncDate = defaults.object(forKey: UDKey.iCloudLastSync) as? Date
    }

    // MARK: - 持ち主の登録と開始

    /// アプリの起動時に1回だけ呼ぶ（AppDelegate から）。記録の持ち主を全員登録して、同期を始める。
    /// ⚠️ 新しく iCloud に入れたい記録を作ったら、ここに登録を足すこと（足さないと、その記録は送られない）。
    static func startAtLaunch() {
        let manager = CloudSyncManager.shared
        manager.register(StickerBookStore.shared)      // シール帳の12ページ（page-01〜page-12）
        manager.register(WallpaperStore.shared)        // かべがみ（wallpaper）
        manager.register(StickerStore.shared)          // もっているシール（stickers）
        manager.register(StickerShop.shared)           // シールやさんの その日の状態（shop）
        manager.register(EnergyStore.shared)           // エネルギー（energy）
        manager.register(ScoreBoardSync.shared)        // ハイスコア・ベストタイム（scores）
        manager.register(ThanksNotebookStore.shared)   // ありがとう てちょう（thanks）
        manager.register(GameRecordSync.shared)        // MAKE10 の Blitz の解放・統計（game）
        manager.start()
    }

    /// 記録の持ち主を登録する。アプリの起動時、start() より前に呼ぶ。
    func register(_ source: CloudSyncSource) {
        for name in source.cloudRecordNames {
            assert(sources[name] == nil, "記録の名前が重なっている: \(name)")
            sources[name] = source
        }
    }

    /// iCloud とのやりとりを始める（オンで、iCloud の機能があるときだけ）。
    /// プライバシーポリシーに同意する前は始めない（同意したときに MakeTenContentView がもう一度呼ぶ）。
    func start() {
        guard Self.isCloudKitConfigured, isEnabled, engine == nil else {
            if !Self.isCloudKitConfigured || !isEnabled { status = .off }
            return
        }
        guard UserDefaults.standard.bool(forKey: UDKey.hasAgreedToTerms) else { return }
        let container = CKContainer(identifier: Self.containerID)
        self.container = container

        // ★ 前回の続きから始める ★
        //   CKSyncEngine は「どこまで受け取ったか」「まだ送っていないもの」を stateSerialization にまとめて渡してくる。
        //   それを保存しておき、次の起動で渡せば、続きから始められる。なければ、はじめてつなぐときの扱い。
        let saved = loadEngineState()
        if saved == nil {
            beginFirstCheck(reason: UserDefaults.standard.object(forKey: UDKey.iCloudCheckReason) as? Int == 1
                            ? .reenabled : .firstConnection)
        }
        var config = CKSyncEngine.Configuration(database: container.privateCloudDatabase,
                                                stateSerialization: saved,
                                                delegate: self)
        config.automaticallySync = true
        engine = CKSyncEngine(config)

        // 記録を入れる区画を用意する（すでにあれば何も起きない）
        engine?.state.add(pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneID: Self.zoneID))])

        // ほかの端末で変わったことを、すぐ知るための知らせ（音も表示もない、目に見えない知らせ）を受け取る
        UIApplication.shared.registerForRemoteNotifications()

        Task { await refreshAccountStatus() }
    }

    // MARK: - 持ち主からの知らせ

    /// 記録が変わったことを知らせる。持ち主が保存するたびに呼ぶ。
    func markChanged(_ name: String) {
        guard let engine, !isApplyingRemote, sources[name] != nil else { return }
        // 2択を待っている間は送らない（選んだあとで、まとめて決める）
        guard !UserDefaults.standard.bool(forKey: UDKey.iCloudNeedsFirstCheck) else { return }
        engine.state.add(pendingRecordZoneChanges: [.saveRecord(recordID(for: name))])
    }

    /// いますぐ iCloud とやりとりする（アプリが前に出てきたときなど）。
    func syncNow() async {
        guard let engine else { return }
        status = .syncing
        do {
            try await engine.fetchChanges()
            try await engine.sendChanges()
            markSynced()
        } catch {
            status = .failed(error.localizedDescription)
        }
    }

    // MARK: - オン／オフ

    /// 保護者が「iCloud に ほぞん」をオン／オフした。
    /// オンに戻したときは、iCloud の記録をはじめから受け取り直し、記録があれば2択を出す。
    func setEnabled(_ on: Bool) {
        guard on != isEnabled else { return }
        isEnabled = on
        UserDefaults.standard.set(on, forKey: UDKey.iCloudSyncOn)
        if on {
            UserDefaults.standard.set(ChoiceReason.reenabled.rawValue, forKey: UDKey.iCloudCheckReason)
            clearEngineState()   // はじめから受け取り直す（続きからだと、iCloud にある記録が全部は届かない）
            start()
        } else {
            stop()
        }
    }

    /// 「さいしょから はじめる」の前に呼ぶ。この端末の同期をオフにして、iCloud の分を残す。
    func disableForReset() {
        setEnabled(false)
    }

    private func stop() {
        engine = nil
        container = nil
        heldRemote = [:]
        needsChoice = false
        status = .off
    }

    // MARK: - 2択

    /// 2択で選ばれた方にそろえる。
    /// - Parameter useCloud: true = iCloud の記録を この端末に もどす / false = この端末の記録で iCloud を うわがき
    func resolveChoice(useCloud: Bool) {
        let held = heldRemote
        heldRemote  = [:]
        needsChoice = false
        endFirstCheck()

        if useCloud {
            applyAll(held, force: true)
        } else {
            // この端末の記録を、iCloud の記録より新しいものとして送る（食い違いでも端末の記録を残す）
            UserDefaults.standard.set(true, forKey: UDKey.iCloudForceUpload)
            queueAllLocal()
        }
        Task { await syncNow() }
    }

    private func beginFirstCheck(reason: ChoiceReason) {
        choiceReason = reason
        UserDefaults.standard.set(true, forKey: UDKey.iCloudNeedsFirstCheck)
        UserDefaults.standard.set(reason.rawValue, forKey: UDKey.iCloudCheckReason)
    }

    private func endFirstCheck() {
        UserDefaults.standard.set(false, forKey: UDKey.iCloudNeedsFirstCheck)
        UserDefaults.standard.set(ChoiceReason.firstConnection.rawValue, forKey: UDKey.iCloudCheckReason)
    }

    /// はじめての受け取りが終わったときに、2択が要るかを決める。
    private func finishFirstCheckIfNeeded() {
        guard UserDefaults.standard.bool(forKey: UDKey.iCloudNeedsFirstCheck), !needsChoice else { return }
        let reasonRaw = UserDefaults.standard.integer(forKey: UDKey.iCloudCheckReason)
        let reason    = ChoiceReason(rawValue: reasonRaw) ?? .firstConnection
        let localHasProgress = sources.values.contains { $0.hasLocalProgress }

        if heldRemote.isEmpty {
            // iCloud にはまだ何もない → この端末の記録を送るだけ
            endFirstCheck()
            queueAllLocal()
        } else if reason == .firstConnection && !localHasProgress {
            // まだ遊んでいない新しい端末 → 聞かずに iCloud の記録を受け取る（機種変更）
            let held = heldRemote
            heldRemote = [:]
            endFirstCheck()
            applyAll(held, force: true)
        } else {
            // 両方に記録がある（またはオンに戻した）→ 保護者に選んでもらう
            choiceReason = reason
            needsChoice  = true
        }
    }

    // MARK: - 反映・送信の下ごしらえ

    /// 届いた記録をまとめて反映する。端末の記録を残したものは送り直す。
    private func applyAll(_ payloads: [String: CloudPayload], force: Bool) {
        for (name, payload) in payloads {
            apply(payload, for: name, force: force)
        }
    }

    private func apply(_ payload: CloudPayload, for name: String, force: Bool) {
        guard let source = sources[name] else { return }
        isApplyingRemote = true
        let result = source.applyCloudPayload(payload, for: name, force: force)
        isApplyingRemote = false
        if result == .keptLocal {
            engine?.state.add(pendingRecordZoneChanges: [.saveRecord(recordID(for: name))])
        }
    }

    /// この端末の記録を、全部送る予定にする。
    private func queueAllLocal() {
        let changes = sources.keys.map { CKSyncEngine.PendingRecordZoneChange.saveRecord(recordID(for: $0)) }
        engine?.state.add(pendingRecordZoneChanges: changes)
    }

    private func recordID(for name: String) -> CKRecord.ID {
        CKRecord.ID(recordName: name, zoneID: Self.zoneID)
    }

    private func markSynced() {
        lastSyncDate = Date()
        UserDefaults.standard.set(lastSyncDate, forKey: UDKey.iCloudLastSync)
        status = .idle
    }

    private func refreshAccountStatus() async {
        guard let container else { return }
        let accountStatus = (try? await container.accountStatus()) ?? .couldNotDetermine
        if accountStatus != .available {
            status = .noAccount
        } else if status == .noAccount || status == .off {
            status = .idle
        }
    }

    // MARK: - CKRecord ⇄ CloudPayload

    /// 送る記録（CKRecord）を作る。前に受け取った「記録の控え」（system fields）があれば、それを土台にする。
    ///
    /// ★ 記録の控えを土台にする理由 ★
    ///   CloudKit は、iCloud にある記録のどの版を土台に書きかえたのかを見て、食い違いを見つける。
    ///   控えなしで新しく作ると、毎回「知らない版」として食い違い扱いになってしまう。
    private func makeRecord(for name: String) -> CKRecord? {
        guard let payload = sources[name]?.cloudPayload(for: name) else { return nil }
        let record = cachedRecord(for: name)
            ?? CKRecord(recordType: Self.recordType, recordID: recordID(for: name))
        record["modifiedAt"] = payload.modifiedAt as CKRecordValue
        if payload.data.count > Self.assetThreshold, let url = writeTempAsset(payload.data, name: name) {
            record["payloadAsset"] = CKAsset(fileURL: url)
            record["payload"]      = nil
        } else {
            record["payload"]      = payload.data as CKRecordValue
            record["payloadAsset"] = nil
        }
        return record
    }

    /// 受け取った記録（CKRecord）から中身を取り出す。
    private func payload(from record: CKRecord) -> CloudPayload? {
        let modifiedAt = record["modifiedAt"] as? Date ?? record.modificationDate ?? .distantPast
        if let data = record["payload"] as? Data {
            return CloudPayload(data: data, modifiedAt: modifiedAt)
        }
        if let asset = record["payloadAsset"] as? CKAsset, let url = asset.fileURL,
           let data = try? Data(contentsOf: url) {
            return CloudPayload(data: data, modifiedAt: modifiedAt)
        }
        return nil
    }

    /// 添付ファイルにするデータを、一時フォルダに書き出す（送り終われば iOS が片づける）。
    private func writeTempAsset(_ data: Data, name: String) -> URL? {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("cloud-\(name)-\(UUID().uuidString).bin")
        do {
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            return nil
        }
    }

    // MARK: - 保存（CKSyncEngine の続き・記録の控え）

    /// Application Support/CloudSync/（端末の中だけのフォルダ。iCloud には送らない）
    private static var folderURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("CloudSync", isDirectory: true)
    }
    private static var stateURL:   URL { folderURL.appendingPathComponent("engine-state.json") }
    private static var recordsURL: URL { folderURL.appendingPathComponent("record-fields.plist") }

    private func loadEngineState() -> CKSyncEngine.State.Serialization? {
        guard let data = try? Data(contentsOf: Self.stateURL) else { return nil }
        return try? JSONDecoder().decode(CKSyncEngine.State.Serialization.self, from: data)
    }

    private func saveEngineState(_ state: CKSyncEngine.State.Serialization) {
        guard let data = try? JSONEncoder().encode(state) else { return }
        try? FileManager.default.createDirectory(at: Self.folderURL, withIntermediateDirectories: true)
        try? data.write(to: Self.stateURL, options: .atomic)
    }

    /// 続きと記録の控えを消す（オンに戻したとき・アカウントが変わったとき）。
    private func clearEngineState() {
        try? FileManager.default.removeItem(at: Self.folderURL)
    }

    /// 記録の控え（名前 → system fields）。
    private func loadRecordFields() -> [String: Data] {
        guard let data = try? Data(contentsOf: Self.recordsURL),
              let dict = try? PropertyListDecoder().decode([String: Data].self, from: data) else { return [:] }
        return dict
    }

    private func cachedRecord(for name: String) -> CKRecord? {
        guard let data = loadRecordFields()[name],
              let coder = try? NSKeyedUnarchiver(forReadingFrom: data) else { return nil }
        coder.requiresSecureCoding = true
        let record = CKRecord(coder: coder)
        coder.finishDecoding()
        return record
    }

    /// 受け取った・送れた記録の控え（system fields だけ。中身は入れない）を残す。
    private func cacheRecordFields(_ record: CKRecord) {
        let coder = NSKeyedArchiver(requiringSecureCoding: true)
        record.encodeSystemFields(with: coder)
        coder.finishEncoding()
        var dict = loadRecordFields()
        dict[record.recordID.recordName] = coder.encodedData
        guard let data = try? PropertyListEncoder().encode(dict) else { return }
        try? FileManager.default.createDirectory(at: Self.folderURL, withIntermediateDirectories: true)
        try? data.write(to: Self.recordsURL, options: .atomic)
    }

    private func removeRecordFields(for name: String) {
        var dict = loadRecordFields()
        dict[name] = nil
        guard let data = try? PropertyListEncoder().encode(dict) else { return }
        try? data.write(to: Self.recordsURL, options: .atomic)
    }

    // MARK: - CKSyncEngine からの知らせを受ける

    fileprivate func handle(_ event: CKSyncEngine.Event) {
        switch event {
        case .stateUpdate(let update):
            saveEngineState(update.stateSerialization)

        case .accountChange(let change):
            handleAccountChange(change)

        case .fetchedRecordZoneChanges(let changes):
            for modification in changes.modifications {
                let record = modification.record
                cacheRecordFields(record)
                guard let payload = payload(from: record) else { continue }
                let name = record.recordID.recordName
                if UserDefaults.standard.bool(forKey: UDKey.iCloudNeedsFirstCheck) {
                    heldRemote[name] = payload   // 2択が要るかわかるまで、反映せずに置いておく
                } else {
                    apply(payload, for: name, force: false)
                }
            }
            // 消えた記録は何もしない（このアプリは iCloud の記録を消さない。リセットでも iCloud の分は残す）

        case .fetchedDatabaseChanges(let changes):
            // 利用者が iPhone の設定から、このアプリの iCloud のデータを消したとき。
            // 端末の記録は消さず、送り直しもしない（消した気持ちを尊重して、同期をオフにする）。
            if changes.deletions.contains(where: { $0.zoneID == Self.zoneID }) {
                clearEngineState()
                setEnabled(false)
            }

        case .didFetchChanges:
            finishFirstCheckIfNeeded()
            markSynced()

        case .sentRecordZoneChanges(let sent):
            handleSent(sent)

        case .willFetchChanges, .willSendChanges:
            status = .syncing

        case .didSendChanges:
            markSynced()

        default:
            break
        }
    }

    private func handleAccountChange(_ change: CKSyncEngine.Event.AccountChange) {
        switch change.changeType {
        case .signIn:
            // サインインした → はじめてつなぐときと同じ扱い（2択が要るか調べる）
            beginFirstCheck(reason: .firstConnection)
            Task { await refreshAccountStatus() }
        case .switchAccounts, .signOut:
            // 別のアカウントになった・サインアウトした → この端末の記録は消さずに残す。
            // 前のアカウントの「続き」と「記録の控え」だけ消す（次のアカウントでは、はじめから）
            clearEngineState()
            heldRemote = [:]
            needsChoice = false
            beginFirstCheck(reason: .firstConnection)
            status = .noAccount
        @unknown default:
            break
        }
    }

    /// 送った結果を見て、食い違い・区画がない・記録が消えている、のときに直して送り直す。
    private func handleSent(_ sent: CKSyncEngine.Event.SentRecordZoneChanges) {
        for record in sent.savedRecords {
            cacheRecordFields(record)
        }
        var retry: [CKSyncEngine.PendingRecordZoneChange] = []
        var needsZone = false
        let forceUpload = UserDefaults.standard.bool(forKey: UDKey.iCloudForceUpload)

        for failure in sent.failedRecordSaves {
            let id   = failure.record.recordID
            let name = id.recordName
            switch failure.error.code {
            case .serverRecordChanged:
                // 食い違い：ほかの端末が先に書きかえていた
                if let server = failure.error.serverRecord {
                    cacheRecordFields(server)
                    if forceUpload {
                        retry.append(.saveRecord(id))   // 2択で「うわがき」を選んだ → 端末の記録で送り直す
                    } else if let remote = payload(from: server) {
                        apply(remote, for: name, force: false)   // 持ち主に決めてもらう（端末を残すなら送り直しが予約される）
                    }
                }
            case .zoneNotFound:
                needsZone = true
                retry.append(.saveRecord(id))
            case .unknownItem:
                // iCloud から記録が消えていた → 控えを捨てて、新しい記録として送り直す
                removeRecordFields(for: name)
                retry.append(.saveRecord(id))
            case .networkFailure, .networkUnavailable, .serviceUnavailable, .requestRateLimited, .zoneBusy:
                break   // CKSyncEngine が、あとで自動で送り直してくれる
            default:
                status = .failed(failure.error.localizedDescription)
            }
        }
        if needsZone {
            engine?.state.add(pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneID: Self.zoneID))])
        }
        if !retry.isEmpty {
            engine?.state.add(pendingRecordZoneChanges: retry)
        }
        // 「うわがき」を選んだ分が、全部送り終わったら印を戻す
        if forceUpload, sent.failedRecordSaves.isEmpty,
           engine?.state.pendingRecordZoneChanges.isEmpty ?? true {
            UserDefaults.standard.set(false, forKey: UDKey.iCloudForceUpload)
        }
    }

    /// 送る記録をまとめて作る（CKSyncEngine に頼まれたとき）。
    ///
    /// ★ 先に全部作ってから渡す理由 ★
    ///   CKSyncEngine は、記録を1つずつ頼む係（recordProvider）を、画面とは別の流れから呼ぶ。
    ///   記録の中身は各ストア（画面の流れで動く）から取り出す必要があるので、
    ///   ここ（画面の流れ）で先に全部作っておき、係にはでき上がった記録を渡すだけにする。
    ///   一度に送るのは多くても十数個（シール帳12ページ＋数個）なので、先に作っても重くない。
    fileprivate func nextBatch(for changes: [CKSyncEngine.PendingRecordZoneChange],
                               engine: CKSyncEngine) async -> CKSyncEngine.RecordZoneChangeBatch? {
        var prepared: [CKRecord.ID: CKRecord] = [:]
        var ready: [CKSyncEngine.PendingRecordZoneChange] = []
        for change in changes {
            guard case .saveRecord(let id) = change else {
                ready.append(change)   // このアプリは記録を消さないが、念のため そのまま渡す
                continue
            }
            if let record = makeRecord(for: id.recordName) {
                prepared[id] = record
                ready.append(change)
            } else {
                // 送るものがない（持ち主がいない・中身がない）→ 予定から外す
                engine.state.remove(pendingRecordZoneChanges: [change])
            }
        }
        let records = prepared
        return await CKSyncEngine.RecordZoneChangeBatch(pendingChanges: ready) { records[$0] }
    }
}

// MARK: - CKSyncEngineDelegate

// ★ nonisolated にしている理由 ★
//   CKSyncEngine は、画面とは別の流れ（バックグラウンド）からこの2つを呼ぶ。
//   このアプリはふだんすべてを画面の流れ（MainActor）で動かしているので、
//   受け取ったら MainActor に乗り換えてから、本体（handle / nextBatch）を呼ぶ。
extension CloudSyncManager: CKSyncEngineDelegate {

    nonisolated func handleEvent(_ event: CKSyncEngine.Event, syncEngine: CKSyncEngine) async {
        await handle(event)
    }

    nonisolated func nextRecordZoneChangeBatch(_ context: CKSyncEngine.SendChangesContext,
                                               syncEngine: CKSyncEngine) async -> CKSyncEngine.RecordZoneChangeBatch? {
        let scope   = context.options.scope
        let changes = syncEngine.state.pendingRecordZoneChanges.filter { scope.contains($0) }
        return await nextBatch(for: changes, engine: syncEngine)
    }
}
