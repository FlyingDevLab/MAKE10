//
//  StickerFace.swift
//  FDL-TenBlitz
//
//  Created by 空飛ぶ研究室(FlyingDevLab) on 2026/11/07.
//
//  シール1枚の見た目。絵文字のシールは文字として、オリジナルシールは画像として出す。
//  シールを画面に出すところは、Text(emoji) の代わりにこれを使う。
//  オリジナルの ID（"custom:..."）は、そのまま文字として出すと意味のない文字列に見えてしまう。

import SwiftUI

struct StickerFace: View {

    /// シールの ID（絵文字そのもの、または "custom:..."）
    let id: String
    /// 絵文字の文字の大きさ（pt）
    let size: CGFloat

    init(_ id: String, size: CGFloat) {
        self.id   = id
        self.size = size
    }

    /// 同じ文字サイズの絵文字とだいたい同じ大きさに見える、画像の1辺の倍率。
    private static let imageRatio: CGFloat = 1.2   // ← 変更可

    var body: some View {
        if CustomStickerStore.isCustom(id) {
            custom
                .frame(width: size * Self.imageRatio, height: size * Self.imageRatio)
                .accessibilityLabel(Text(verbatim: Self.spokenName(id)))
        } else {
            Text(id)
                .font(.system(size: size))
        }
    }

    @ViewBuilder
    private var custom: some View {
        if let image = CustomStickerStore.shared.image(for: id) {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
        } else {
            // 別の端末で作ったシールの画像が、まだ iCloud から届いていないとき
            RoundedRectangle(cornerRadius: size * 0.15)
                .fill(Color.black.opacity(0.08))
        }
    }

    /// シールを文章や読み上げに入れるときの文字（絵文字はそのまま、オリジナルは名前）。
    static func spokenName(_ id: String) -> String {
        guard CustomStickerStore.isCustom(id) else { return id }
        let name = CustomStickerStore.shared.sticker(for: id)?.name ?? ""
        return name.isEmpty ? String(localized: "sticker_custom_default_name") : name
    }
}
