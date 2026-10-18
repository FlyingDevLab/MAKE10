//
//  ScreenshotMode.swift
//  FDL-TenBlitz
//
//  Created by 空飛ぶ研究室(FlyingDevLab) on 2026/10/18.
//
//  App Store 用のスクリーンショットを、シミュレータで自動で撮るための「撮影モード」。
//  起動するときに場面を指定すると、その画面をすぐに開き、ゲームを少し進めた状態にする。
//
//  使い方（ターミナル）:
//    xcrun simctl launch <端末> com.flyingdevlab.FDL-TenBlitz -ssScene quiz -AppleLanguages "(de)"
//    → 数秒待ってから xcrun simctl io <端末> screenshot で撮る
//    まとめて撮るスクリプトは AppStoreScreenshots/capture.sh
//
//  ★ リリース版では動かない ★
//    場面を読み取るのは DEBUG ビルド（Xcode で Run したもの）のときだけ。
//    App Store に出すビルド（Release）では scene がいつも nil になり、何も起きない。
//    呼び出す側に #if DEBUG を書かずに済むよう、この型自体はどちらのビルドにも入れている。
//
//  ★ 起動引数がそのまま設定値として読める理由 ★
//    「-ssScene quiz」のように「-名前 値」で起動すると、iOS はそのアプリの UserDefaults に
//    一時的な値として入れてくれる（保存はされない）。次にふつうに起動すれば消えている。
//

import Foundation

// MARK: - ScreenshotScene

/// 撮影する場面。名前は起動引数 -ssScene に書く値。
enum ScreenshotScene: String {
    case title        // タイトル画面（ゲーム一覧）
    case make10       // MAKE10 の30びょうモードのプレイ中
    case tenPuzzle    // テンパズルで式を組み立てたところ
    case memory       // どうぶつめくり 5×5（まん中にロゴ）で、何組かそろえたところ
    case quiz         // 絵文字クイズ（ヨーロッパの国旗）で正解したところ
    case sticker      // シール帳であそぶ画面
    case janken       // しれいじゃんけんのプレイ中
    case maze         // 迷路のプレイ中
    case whackAMole   // もぐらたたきのプレイ中
    case pinball      // ピンボールのプレイ中
    case coinDrop     // コインドロップのプレイ中
    case shop         // シールやさん
    case gacha        // ガチャ
    case stickerDex   // シールじてん
    case thanks       // ありがとう てちょう
}

// MARK: - ScreenshotMode

enum ScreenshotMode {

    /// 起動引数で指定された場面。指定がないとき・リリース版では nil。
    static let scene: ScreenshotScene? = {
        #if DEBUG
        return UserDefaults.standard.string(forKey: "ssScene").flatMap(ScreenshotScene.init)
        #else
        return nil
        #endif
    }()

    /// 撮影モードで起動しているか。お知らせ・休憩のカード、タイトルの自動デモを止めるのに使う。
    static var isActive: Bool { scene != nil }

    /// 指定の秒数だけ待ってから action を行う。ゲームが始まるのを待って操作するときに使う。
    static func after(_ seconds: Double, _ action: @escaping @MainActor () -> Void) {
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(seconds))
            action()
        }
    }
}
