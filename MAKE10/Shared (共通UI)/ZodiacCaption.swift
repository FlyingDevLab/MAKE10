//
//  ZodiacCaption.swift
//  FDL-TenBlitz
//
//  Created by 空飛ぶ研究室(FlyingDevLab) on 2026/10/16.
//
//  星座のシール（♈〜♓）を手に入れたときに、その下に出す「名前と絵」（例: 「おひつじ座 🐏」）。
//  星座でない絵文字のときは何も出さない。
//
//  使っている場所:
//    - MemoryResultView  : どうぶつめくりで、えらんだシールを大きく出すところ
//  ガチャ・シールやさんでは出さない（ユーザーと決めた方針。星座を覚えるのは、どうぶつめくりの「せいざ」で）。
//  別の場所にも出したくなったら、その画面に ZodiacCaption(emoji:) を1行足すだけでよい。
//
//  ★ ねらい ★
//    ♈ のような記号だけでは、何の星座か分からない。もらった瞬間に名前と絵をそえて、
//    「これは おひつじ座で、ひつじの形なんだ」と覚えるきっかけにする。
//
//  ★ 絵（🐏 など）はシールにしない ★
//    ここで出す絵は、星座の意味を伝えるための「説明の絵」で、シールではない。
//    シールの名簿（StickerCatalog）・じてんには入れない（ユーザーと決めた方針）。
//    そのため、シールには入れない人物（👬 👩）や 🏹 も、星座の意味を正しく伝えるためにここでは使う。
//
//  ★ 名前の訳 ★
//    どうぶつめくりの読み上げ用に作った星座の名前（memory_zodiac_*、15言語）をそのまま使う。

import SwiftUI

// MARK: - ZodiacCaption

/// 星座のシールの下に出す「名前と絵」。星座でなければ何も出さない（EmptyView）。
struct ZodiacCaption: View {

    /// 手に入れたシールの絵文字。
    let emoji: String

    /// 文字の大きさ。← 変更可（使う場所に合わせて渡す）
    var fontSize: CGFloat = 16

    var body: some View {
        if let zodiac = MemoryZodiac(emoji: emoji) {
            HStack(spacing: 6) {
                Text(zodiac.accessibilityLabel)
                    .font(.system(size: fontSize, weight: .heavy, design: .rounded))
                    .foregroundStyle(DS.textPrimary)
                Text(verbatim: zodiac.motif)
                    .font(.system(size: fontSize * 1.4))
                    .accessibilityHidden(true)   // 名前を読めば足りるので、絵は読み上げない
            }
            .lineLimit(1)
            .minimumScaleFactor(0.6)
        }
    }
}
