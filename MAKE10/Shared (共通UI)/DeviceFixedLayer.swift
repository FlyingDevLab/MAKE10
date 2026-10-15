//
//  DeviceFixedLayer.swift
//  FDL-TenBlitz
//
//  Created by 空飛ぶ研究室(FlyingDevLab) on 2026/10/15.
//
//  中身を「端末に対して」縦向きに止めておく入れ物。
//  iPad を横にすると、ボタンや文字は画面と一緒に横を向くが、この中身だけは逆向きに回して、
//  端末から見ると縦のときと同じ場所・同じ向きのままにする。
//
//  使っている場所:
//    - StickerPlayView : シール帳の紙（背景色・お絵かき・シール）
//    - AppBackground（WallpaperStore.swift）: かべがみ
//
//  ★ なぜ「逆向きに回す」と止まって見えるのか ★
//    iPad を時計回りに90°回すと、iOS は画面の中身を反時計回りに90°回して、文字がまっすぐ読めるようにする。
//    そこで、この入れ物の中身だけを時計回りに90°回し直せば、2つの回転が打ち消し合い、
//    中身は端末に貼りついたように動かない。
//
//  ★ 中身に渡す大きさ ★
//    横向きのときは、中身を90°回すので、中身にとっての幅と高さは入れ物の逆になる。
//    たとえば横長 1194×834 の画面なら、中身には縦長 834×1194 として渡す。
//    回したあとは、ちょうど入れ物いっぱいに重なる。
//
//  ★ 分割表示・Stage Manager のウィンドウでも回す ★（ユーザーと決めた「A」）
//    ウィンドウでも、端末の向き（画面の向き）に合わせて回す。中身は、渡された大きさの中に
//    自分で収まるように置く（シール帳の紙は縦横比を保って縮める、など）。
//    こうすると「絵はいつも端末に対して縦向き」というルールひとつで済む。
//
//  ★ 指の位置について ★
//    .rotationEffect で回した中身の中では、ジェスチャーが返す指の位置も、回す前の向き
//    （中身にとっての縦向き）に直して渡される。なので中身の側では、回っていることを気にせずに
//    今までどおりの位置で線を描いたり、シールを動かしたりできる。

import SwiftUI
import UIKit

// MARK: - DeviceFixedLayer

/// 中身を端末に対して縦向きに止めておく入れ物。
/// content には「中身にとっての大きさ（いつも端末を縦にしたときの向き）」が渡される。
struct DeviceFixedLayer<Content: View>: View {

    /// 中身を作るクロージャ。引数は中身にとっての大きさ。
    @ViewBuilder let content: (CGSize) -> Content

    /// いまの画面の向き（InterfaceOrientationWatcher が見張っていて、変わると描き直される）。
    @State private var watcher = InterfaceOrientationWatcher.shared

    var body: some View {
        GeometryReader { geo in
            let angle   = DeviceFixedRotation.counterAngle(for: watcher.orientation)
            // 90°・270° 回すときは、中身にとっての幅と高さが入れ物の逆になる
            let inner = DeviceFixedRotation.isQuarter(angle)
                ? CGSize(width: geo.size.height, height: geo.size.width)
                : geo.size

            content(inner)
                .frame(width: inner.width, height: inner.height)
                .rotationEffect(.degrees(angle))
                // 回したあと、入れ物のまん中に置く
                .position(x: geo.size.width / 2, y: geo.size.height / 2)
        }
        .onGeometryChange(for: CGSize.self) { proxy in
            proxy.size
        } action: { _ in
            // 分割表示・Stage Manager で大きさが変わったときにも、念のため向きを読み直す
            watcher.refresh()
        }
    }
}

// MARK: - InterfaceOrientationWatcher

/// 画面の向きを見張るシングルトン。向きが変わると orientation が変わり、見ている画面が描き直される。
///
/// ★ 画面の大きさだけでなく、端末の向きの知らせでも読み直す理由 ★
///   最初は「画面の大きさが変わったら向きを読み直す」だけにしていた。ところが、横から反対の横へ
///   一気に180°回すと、画面の幅と高さは変わらない。すると向きを読み直さず、前の角度のまま
///   逆さまに回してしまった（iPhone で、回し方によって絵が逆を向いた）。
///   そこで、端末の向きが変わったという iOS の知らせ（UIDevice.orientationDidChangeNotification）でも読み直す。
///
/// ★ 知らせが来たあと、少し待ってもう一度読む理由 ★
///   知らせは「端末が回った」瞬間に届くが、画面の向き（アプリの文字やボタンの向き）が切り替わるのは
///   回転のアニメーションが始まってから。すぐに読むと前の向きのことがあるので、少し待って読み直す。
// @Observable / シングルトンの解説は AppSettings.swift 冒頭を参照
@Observable
final class InterfaceOrientationWatcher {

    static let shared = InterfaceOrientationWatcher()

    /// 知らせが来てから、もう一度読み直すまでの時間（秒）← 変更可
    private static let settleDelay: Double = 0.3

    /// いまの画面の向き。
    private(set) var orientation: UIInterfaceOrientation = DeviceFixedRotation.currentOrientation()

    private init() {
        // 端末の向きの知らせを出してもらう（ふつうは UIKit がすでに出しているが、念のため）
        UIDevice.current.beginGeneratingDeviceOrientationNotifications()
        NotificationCenter.default.addObserver(
            forName: UIDevice.orientationDidChangeNotification, object: nil, queue: .main
        ) { _ in
            Task { @MainActor in
                let watcher = InterfaceOrientationWatcher.shared
                watcher.refresh()
                try? await Task.sleep(for: .seconds(Self.settleDelay))
                watcher.refresh()
            }
        }
    }

    /// 画面の向きを読み直す（変わっていなければ何もしない＝余計な描き直しをしない）。
    func refresh() {
        let now = DeviceFixedRotation.currentOrientation()
        if now != orientation { orientation = now }
    }
}

// MARK: - DeviceFixedRotation

/// 画面の向きと、端末に対して止めるために回す角度を求める道具。
/// DeviceFixedLayer のほか、回した紙の上の位置と画面全体の位置を行き来する StickerPlayView でも使う。
/// （DeviceFixedLayer は中身の型をあとから決める「ジェネリクス」の型なので、
///   どこからでも呼べるよう、角度の計算はこちらの型に分けている）
enum DeviceFixedRotation {

    /// いまの画面の向きを、表に出ているウィンドウシーンから読む。読めなければ縦とみなす。
    static func currentOrientation() -> UIInterfaceOrientation {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let scene  = scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
        return scene?.effectiveGeometry.interfaceOrientation ?? .portrait
    }

    /// 画面の向きに対して、中身を何度回せば端末に対して止まって見えるか（時計回りが +）。
    ///
    /// ★ UIInterfaceOrientation の名前の読み方 ★
    ///   .landscapeLeft  … ホームボタン（今はない機種もある）が左にくる向き ＝ 端末を時計回りに90°回した状態
    ///   .landscapeRight … ホームボタンが右にくる向き ＝ 端末を反時計回りに90°回した状態
    ///   端末を時計回りに回したら、中身も時計回り（+90°）に回し直すと、端末に対して止まって見える。
    ///   ⚠️ 実機・シミュレータで ⌘← ⌘→ の両方を確かめること。逆に回るなら、下の 90 と -90 を入れ替える。
    static func counterAngle(for orientation: UIInterfaceOrientation) -> Double {
        switch orientation {
        case .landscapeLeft:      return 90    // ← 確認用（逆なら -90）
        case .landscapeRight:     return -90   // ← 確認用（逆なら 90）
        case .portraitUpsideDown: return 180
        default:                  return 0     // 縦（と、向きがわからないとき）は回さない
        }
    }

    /// 回す角度が 90° か -90° か（そのときは、中身にとっての幅と高さが入れ物の逆になる）。
    static func isQuarter(_ angle: Double) -> Bool { abs(angle) == 90 }
}
