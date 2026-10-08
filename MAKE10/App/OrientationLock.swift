//
//  OrientationLock.swift
//  FDL-TenBlitz
//
//  Created by 空飛ぶ研究室(FlyingDevLab) on 2026/10/08.
//
//  「いま画面をどの向きにしてよいか」をアプリ全体で1か所に持つ係。
//  ふだんは Info.plist で許可した向き（iPad は縦横、iPhone は縦）を使い、
//  縦で遊ぶゲーム（Pinball・CoinDrop・TenPuzzle）を開いているあいだだけ「縦のみ」に絞る。
//
//  役割分担:
//    - OrientationLock（このファイル）: 許可する向きの保持と、iOS への「向きを見直して」のお願い
//    - AppDelegate（このファイル）      : iOS に「いま許可している向き」を答える窓口
//    - FDL_TenBlitzApp                  : AppDelegate をアプリにつなぐ
//    - MakeTenContentView               : 開いている画面に合わせて setPortraitOnly を呼ぶ
//
//  ★ 向きの固定は「できるときだけ効く」★
//    iPad の分割表示・Stage Manager のウィンドウ表示・iPhone Duo を開いたときなどは、
//    アプリが向きを決められないので、ここで「縦のみ」にしても画面は回らない。
//    そのため縦で遊ぶゲームは、横長の場所に置かれても崩れないよう、
//    盤面を中央に置いて左右を余白にする表示も持たせている（MakeTenContentView を参照）。
//    この係は「回せるなら縦に回す」までを担当し、回せなかったときの見た目は担当しない。

import SwiftUI
import UIKit

// MARK: - OrientationLock

final class OrientationLock {

    static let shared = OrientationLock()

    // MARK: 状態

    /// いま許可している向き。AppDelegate がこの値を iOS に答える。
    private(set) var mask: UIInterfaceOrientationMask

    // MARK: 初期化

    private init() {
        mask = Self.infoPlistMask
    }

    // MARK: 向きの切り替え

    /// 縦のみにするか（true）、Info.plist で許可した向きに戻すか（false）を切り替える。
    ///
    /// ★ 2段階で iOS にお願いする理由 ★
    ///   ① setNeedsUpdateOfSupportedInterfaceOrientations
    ///      「許可する向きが変わったので、AppDelegate に聞き直して」と iOS に伝える。
    ///      縦のみ → 縦横OK に戻すときは、これだけで端末の向きに合わせて自然に回る。
    ///   ② requestGeometryUpdate
    ///      端末が横向きのまま縦のみのゲームを開いたときは、①だけでは回らないことがあるので、
    ///      「いますぐ縦に回して」とはっきりお願いする。
    func setPortraitOnly(_ portraitOnly: Bool) {
        let newMask: UIInterfaceOrientationMask = portraitOnly ? .portrait : Self.infoPlistMask
        guard newMask != mask else { return }   // 変わらないなら、iOS に何も頼まない
        mask = newMask

        for scene in UIApplication.shared.connectedScenes {
            guard let windowScene = scene as? UIWindowScene else { continue }
            windowScene.keyWindow?.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
            if portraitOnly {
                // 分割表示などで回せないときはエラーが返るが、それで正常（上の「★ 向きの固定は…」を参照）。
                // 盤面は中央に置く表示で崩れないので、ここでは何もしない。
                windowScene.requestGeometryUpdate(.iOS(interfaceOrientations: newMask)) { _ in }
            }
        }
    }

    // MARK: Info.plist の読み取り

    /// Info.plist の UISupportedInterfaceOrientations を、向きの集まり（mask）に直したもの。
    ///
    /// ★ iPad と iPhone で別の値が返る理由 ★
    ///   Info.plist には「iPad 用」の向き（キー名の末尾が ~ipad）を別に書ける。
    ///   Bundle はアプリが動いている端末に合う方を自動で選んで返すので、
    ///   ここで端末の種類を調べなくても、iPad では縦横・iPhone では縦が手に入る。
    ///   読めなかったときは、いちばん安全な「縦のみ」にする。
    private static var infoPlistMask: UIInterfaceOrientationMask {
        let names = Bundle.main.object(forInfoDictionaryKey: "UISupportedInterfaceOrientations") as? [String] ?? []
        var result: UIInterfaceOrientationMask = []
        for name in names {
            switch name {
            case "UIInterfaceOrientationPortrait":           result.insert(.portrait)
            case "UIInterfaceOrientationPortraitUpsideDown": result.insert(.portraitUpsideDown)
            case "UIInterfaceOrientationLandscapeLeft":      result.insert(.landscapeLeft)
            case "UIInterfaceOrientationLandscapeRight":     result.insert(.landscapeRight)
            default:                                         break
            }
        }
        return result.isEmpty ? .portrait : result
    }
}

// MARK: - AppDelegate

/// iOS から「このアプリはいまどの向きにしてよい？」と聞かれたときの窓口。
///
/// ★ SwiftUI のアプリなのに AppDelegate を使う理由 ★
///   SwiftUI だけでは「アプリ全体で許可する向き」をあとから変える方法がない。
///   UIKit の AppDelegate にある application(_:supportedInterfaceOrientationsFor:) を使うと、
///   iOS が向きを決めるたびにこのメソッドを呼んでくれるので、そこで OrientationLock の値を返す。
///   AppDelegate をアプリにつなぐのは FDL_TenBlitzApp の @UIApplicationDelegateAdaptor。
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        OrientationLock.shared.mask
    }
}
