//
//  WallpaperStore.swift
//  FDL-TenBlitz
//
//  Created by 空飛ぶ研究室(FlyingDevLab) on 2026/10/05.
//
//  かべがみ（お絵かき画面で描いた絵を、アプリの背景にする）を持つシングルトンと、背景を描くビュー。
//
//  役割分担:
//    - WallpaperStore（このファイル）: かべがみの画像の保存・読み込みと、使うかどうかの設定
//    - AppBackground（このファイル） : 背景を描く。かべがみを使うなら絵、使わないならいつもの色（DS.bg）
//    - StickerPlayView              : 「かべがみに する」ボタンで、いまの絵（線＋シール）を画像にして渡す
//    - SettingsView                 : 「かべがみ」のオン／オフ
//
//  「さいしょから はじめる」では、お絵かきの線と一緒にかべがみも消す（GameViewModel.resetProgress）。
//
//  ★ 画像で保存している理由 ★
//    お絵かきの線は「指でなぞった点の列」として、描いた画面の大きさのまま保存されている。
//    背景に使うたびに描き直すと、画面の大きさや向きが違うときに位置がずれてしまう。
//    「かべがみに する」を押した瞬間の見た目をそのまま画像にしておけば、あとで描き足しても
//    かべがみは変わらず、どの画面でも同じ絵を出せる。
//
//  ★ iCloud との同期 ★（CloudSyncManager.swift を参照）
//    画像・帯の色・オン／オフをまとめて1つの記録（"wallpaper"）にする。2台で食い違ったら、あとで変えたほうを残す。

import SwiftUI

// MARK: - WallpaperStore

// @Observable / シングルトンの解説は AppSettings.swift 冒頭を参照
@Observable
final class WallpaperStore {

    static let shared = WallpaperStore()

    /// かべがみの画像（まだ作っていなければ nil）。
    private(set) var image: UIImage?

    /// かべがみを背景に使うか（設定でオン／オフできる）。
    var isOn: Bool {
        didSet {
            UserDefaults.standard.set(isOn, forKey: UDKey.isWallpaperOn)
            if !isApplyingCloud { touch() }
        }
    }

    /// iCloud から届いたかべがみを反映している間 true（その間の変更は「変えた」扱いにしない）。
    private var isApplyingCloud = false

    /// いま背景にかべがみを出すか（オンで、画像があるとき）。
    var isShowing: Bool { isOn && image != nil }

    /// かべがみの絵の背景色（お絵かき画面で選んでいた色）。
    private(set) var paperColor: Color?

    /// ヘッダーとフッターの帯の色。
    ///
    /// ★ かべがみのときは、絵の背景色で塗る理由 ★
    ///   帯は文字を読みやすくするために塗っている（SharedFrame を参照）。
    ///   いつもの色（DS.bg）で塗ると、絵の上下にだけ別の色の帯ができて目立ってしまう。
    ///   絵の背景色と同じ色で塗れば、帯が絵になじむ。
    var bandColor: Color {
        isShowing ? (paperColor ?? DS.bg) : DS.bg
    }

    private init() {
        isOn  = UserDefaults.standard.bool(forKey: UDKey.isWallpaperOn)
        image = (try? Data(contentsOf: Self.fileURL)).flatMap(UIImage.init(data:))
        if let rgb = UserDefaults.standard.array(forKey: UDKey.wallpaperBandRGB) as? [Double], rgb.count == 3 {
            paperColor = Color(red: rgb[0], green: rgb[1], blue: rgb[2])
        }
    }

    /// 新しいかべがみを保存して、背景に使い始める。
    /// - Parameter paper: 絵の背景色（ヘッダー・フッターの帯に使う）
    func save(_ newImage: UIImage, paper: Color) {
        guard let data = newImage.pngData() else { return }
        try? data.write(to: Self.fileURL, options: .atomic)
        image = newImage
        isOn  = true
        touch()

        // Color のままでは保存できないので、赤・緑・青の割合にして保存する
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        if UIColor(paper).getRed(&r, green: &g, blue: &b, alpha: &a) {
            UserDefaults.standard.set([Double(r), Double(g), Double(b)], forKey: UDKey.wallpaperBandRGB)
            paperColor = Color(red: Double(r), green: Double(g), blue: Double(b))
        }
    }

    /// 「さいしょから はじめる」で、かべがみを消して、いつもの背景に戻す。
    func reset() {
        try? FileManager.default.removeItem(at: Self.fileURL)
        UserDefaults.standard.removeObject(forKey: UDKey.wallpaperBandRGB)
        UserDefaults.standard.removeObject(forKey: Self.modifiedAtKey)
        image      = nil
        paperColor = nil
        isOn       = false
    }

    /// 保存先: Documents/wallpaper.png（お絵かきの drawing_canvas.json と同じ場所）
    private static var fileURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("wallpaper.png")
    }

    // MARK: iCloud との同期

    /// かべがみを最後に変えた時刻を保存するキー（iCloud で2台の食い違いを比べるときに使う）。
    private static let modifiedAtKey = "wallpaperModifiedAt"

    /// 最後に変えた時刻を今にして、iCloud に送る予定にする（iCloud を使っていなければ何も起きない）。
    private func touch() {
        UserDefaults.standard.set(Date(), forKey: Self.modifiedAtKey)
        CloudSyncManager.shared.markChanged(Self.recordName)
    }

    private static let recordName = "wallpaper"

    /// iCloud に送る中身。
    private struct CloudWallpaper: Codable {
        var png:  Data?       // 画像（まだ作っていなければ nil）
        var rgb:  [Double]?   // 帯の色 [r, g, b]
        var isOn: Bool
    }
}

// MARK: - iCloud との同期（CloudSyncSource）

extension WallpaperStore: CloudSyncSource {

    var cloudRecordNames: [String] { [Self.recordName] }

    func cloudPayload(for name: String) -> CloudPayload? {
        let wallpaper = CloudWallpaper(
            png:  try? Data(contentsOf: Self.fileURL),
            rgb:  UserDefaults.standard.array(forKey: UDKey.wallpaperBandRGB) as? [Double],
            isOn: isOn
        )
        // ★ PropertyList（バイナリ）にする理由 ★
        //   JSON だと画像のデータが文字に直されて 3割ほど大きくなる。バイナリの PropertyList なら、そのままの大きさで入る。
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        guard let data = try? encoder.encode(wallpaper) else { return nil }
        let modifiedAt = UserDefaults.standard.object(forKey: Self.modifiedAtKey) as? Date ?? .distantPast
        return CloudPayload(data: data, modifiedAt: modifiedAt)
    }

    /// iCloud から届いたかべがみを反映する。あとで変えたほうを残す。
    func applyCloudPayload(_ payload: CloudPayload, for name: String, force: Bool) -> CloudApplyResult {
        guard let remote = try? PropertyListDecoder().decode(CloudWallpaper.self, from: payload.data) else {
            return .applied
        }
        let localDate = UserDefaults.standard.object(forKey: Self.modifiedAtKey) as? Date ?? .distantPast
        if !force && localDate > payload.modifiedAt {
            return .keptLocal   // この端末のほうがあとで変えた → この端末のかべがみを送り直す
        }

        isApplyingCloud = true
        defer { isApplyingCloud = false }

        if let png = remote.png, let newImage = UIImage(data: png) {
            try? png.write(to: Self.fileURL, options: .atomic)
            image = newImage
        } else {
            try? FileManager.default.removeItem(at: Self.fileURL)
            image = nil
        }
        if let rgb = remote.rgb, rgb.count == 3 {
            UserDefaults.standard.set(rgb, forKey: UDKey.wallpaperBandRGB)
            paperColor = Color(red: rgb[0], green: rgb[1], blue: rgb[2])
        } else {
            UserDefaults.standard.removeObject(forKey: UDKey.wallpaperBandRGB)
            paperColor = nil
        }
        isOn = remote.isOn
        UserDefaults.standard.set(payload.modifiedAt, forKey: Self.modifiedAtKey)
        return .applied
    }

    /// かべがみを作ったことがあれば「遊んだ」とみなす。
    var hasLocalProgress: Bool { image != nil }
}

// MARK: - AppBackground

/// アプリの背景。かべがみを使うなら絵を、使わないならいつもの色を、画面いっぱいに描く。
///
/// ★ 絵の合わせ方 ★
///   縦横の比率は変えずに、画面いっぱいになるまで広げ、はみ出した分は切る（scaledToFill）。
///   分割表示のウィンドウなど、描いたときと画面の形が違っても、絵がゆがまない。
///
/// ★ 絵は端末に対して縦向きに止める ★（DeviceFixedLayer.swift を参照）
///   端末を横にしても、ボタンや文字だけが横を向き、かべがみの絵は端末に貼りついたまま動かない。
///   シール帳の紙と同じ考え方なので、描いた絵が、描いたときと同じ向きで背景に出る。
///   全画面で横にしたときは、縦長の絵が90°回って、ちょうど横長の画面いっぱいに重なる。
struct AppBackground: View {
    private let wallpaper = WallpaperStore.shared

    var body: some View {
        if wallpaper.isShowing, let image = wallpaper.image {
            DeviceFixedLayer { size in
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: size.width, height: size.height)
                    .clipped()
            }
            // 絵がウィンドウの形に合わず、回したときに隅がわずかに空いても目立たないよう、絵の背景色を敷く
            .background(wallpaper.paperColor ?? DS.bg)
            .accessibilityHidden(true)
        } else {
            DS.bg
        }
    }
}
