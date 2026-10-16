//
//  ScrollIfNeeded.swift
//  FDL-TenBlitz
//
//  Created by 空飛ぶ研究室(FlyingDevLab) on 2026/10/16.
//
//  中身が縦に「収まるときはそのまま」「収まらないときだけスクロール」にする入れ物。
//
//  使っている場所:
//    - SettingsView      : 設定パネル・リセットの確認・iCloud のえらぶ画面
//    - StickerDexView    : シールをエネルギーに交換するカード
//    - MazeGameView      : 迷路の遊び方カード・結果
//  どうぶつめくりのスタート画面（MemoryGameView）は、並べ方を3つから選ぶので ViewThatFits を直接使っている。
//
//  ★ なぜ ScrollView にいつも入れず、この入れ物を使うのか ★
//    ScrollView に入れると、中身は「上に詰めて」置かれ、Spacer で上下中央にそろえる並べ方が効かなくなる。
//    iPhone の縦や iPad のように高さが足りる場所では、今までと同じ見た目のままにしたい。
//    そこで ViewThatFits を使う。ViewThatFits は、上から順に「収まるもの」を1つだけ選ぶ。
//      ① 中身そのまま（収まるとき。今までと同じ見た目）
//      ② 中身を ScrollView に入れたもの（iPhone の横向き・文の長い言語などで、収まらないとき）
//
//  ★ 以前は同じ4行を8か所に書いていた ★
//    考え方を1か所にまとめ、どの画面も同じ動き（はね返りは中身が長いときだけ、など）になるようにした。
//

import SwiftUI

// MARK: - ScrollIfNeeded

/// 縦に収まるときはそのまま、収まらないときだけスクロールさせる入れ物。
///
/// 使い方:
/// ```swift
/// ScrollIfNeeded {
///     howToCard
/// }
/// ```
struct ScrollIfNeeded<Content: View>: View {

    /// 中に入れる中身。①と②の両方で同じものを使う。
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        ViewThatFits(in: .vertical) {
            content
            ScrollView { content }
                // 中身が画面より短いときは、引っぱっても はね返らないようにする
                .scrollBounceBehavior(.basedOnSize)
        }
    }
}
