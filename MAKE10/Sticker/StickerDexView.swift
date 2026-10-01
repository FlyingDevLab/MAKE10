//
//  StickerDexView.swift
//  FDL-TenBlitz
//
//  Created by 空飛ぶ研究室(FlyingDevLab) on 2026/10/02.
//
//  シールじてん。手に入るシールの全種類をカテゴリごとに並べ、
//  手に入れたシールは持っている枚数と一緒に、まだのシールは黒いシルエットで見せる。
//
//  役割分担:
//    - StickerDexView（このファイル）: 一覧の表示（見るだけ。シールを動かす操作はない）
//    - StickerCatalog                : どんなシールがあるか（カテゴリと並び順）
//    - StickerStore                  : いま持っている枚数（ownedCounts）
//
//  ★ 「持っている枚数」を「手に入れたかどうか」の判定に使える理由 ★
//    シールを捨てる・消す方法はない（進捗リセットを除く）ので、
//    1枚でも持っていれば「手に入れたことがある」と言える（StickerStore.ownedCounts を参照）。
//
//  ★ このファイルの構成 ★
//    StickerDexView … 画面本体（あつめた数・カテゴリごとの一覧・とじるボタン）
//    StickerDexCell … 一覧の1マス（シール1種類分）

import SwiftUI

// MARK: - StickerDexView

struct StickerDexView: View {

    // MARK: 依存

    @Environment(\.dismiss) private var dismiss

    // MARK: 表示用の値

    /// シールの種類ごとの所有数。画面を開いたときに一度だけ数える（じてんを見ている間は変わらないため）。
    private let owned = StickerStore.shared.ownedCounts()

    /// あつめた種類の数（全シールのうち、1枚以上持っているもの）。
    private var collectedCount: Int {
        StickerCatalog.all.filter { owned[$0, default: 0] > 0 }.count
    }

    // MARK: body

    var body: some View {
        VStack(spacing: 0) {
            header

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 20, pinnedViews: [.sectionHeaders]) {
                    ForEach(StickerCatalog.categories) { category in
                        Section {
                            LazyVGrid(
                                columns: [GridItem(.adaptive(minimum: 64), spacing: 8)],   // ← 変更可（マスの最小幅）
                                spacing: 8
                            ) {
                                ForEach(category.emojis, id: \.self) { emoji in
                                    StickerDexCell(emoji: emoji, count: owned[emoji, default: 0])
                                }
                            }
                        } header: {
                            categoryHeader(category)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 32)
            }
        }
        .background(DS.bg.ignoresSafeArea())
    }

    // MARK: サブビュー

    /// 上の帯：タイトル・あつめた数・とじるボタン。
    private var header: some View {
        VStack(spacing: 10) {
            HStack {
                Text("sticker_dex_title")
                    .font(.system(size: 24, weight: .black, design: .rounded))
                    .foregroundStyle(DS.primary)
                Spacer()
                Button {
                    SoundManager.shared.playTap()
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(DS.muted)
                        .frame(width: 40, height: 40)
                        .background(Circle().fill(Color.black.opacity(0.05)))
                }
                .buttonStyle(.plain)
            }

            // あつめた数と、進み具合のバー
            let total = StickerCatalog.all.count
            VStack(spacing: 6) {
                Text("sticker_dex_progress \(collectedCount) \(total)")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(DS.textBody)
                    .frame(maxWidth: .infinity, alignment: .leading)
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.black.opacity(0.08))
                        Capsule()
                            .fill(DS.energy)
                            .frame(width: geo.size.width * CGFloat(collectedCount) / CGFloat(max(total, 1)))
                    }
                }
                .frame(height: 10)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 20)
        .padding(.bottom, 12)
    }

    /// カテゴリの見出し。そのカテゴリで何種類あつめたかも出す。
    private func categoryHeader(_ category: StickerCatalog.Category) -> some View {
        let got = category.emojis.filter { owned[$0, default: 0] > 0 }.count
        // ⚠️ 変更注意: キーは文字列の連結で作ること。LocalizedStringKey の中で "\(...)" と埋め込むと
        //   「sticker_category_%@」という別のキーとして扱われ、翻訳が見つからなくなる。
        let titleKey = LocalizedStringKey("sticker_category_" + category.id)
        return HStack {
            Text(titleKey)
                .font(.system(size: 17, weight: .black, design: .rounded))
                .foregroundStyle(DS.textPrimary)
            Spacer()
            Text(verbatim: "\(got) / \(category.emojis.count)")
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(got == category.emojis.count ? DS.energy : DS.muted)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 4)
        .background(DS.bg)   // スクロールしたとき、見出しの後ろにシールが透けないようにする
    }
}

// MARK: - StickerDexCell

/// じてんの1マス。手に入れたシールは色つきで枚数を、まだのシールは黒いシルエットで出す。
private struct StickerDexCell: View {
    let emoji: String
    let count: Int

    private var isCollected: Bool { count > 0 }

    var body: some View {
        Text(emoji)
            .font(.system(size: 36))   // ← 変更可（シールの大きさ）
            // ★ 絵文字を黒いシルエットにする方法 ★
            //   絵文字はカラーの画像なので、文字色（foregroundStyle）では色を変えられない。
            //   colorMultiply(.black) は「すべての色に黒を掛ける」ので、透明な部分はそのままに
            //   形だけが真っ黒になる。どんなシールか、形だけを見て想像する楽しみを残せる。
            .colorMultiply(isCollected ? .white : .black)
            .opacity(isCollected ? 1.0 : 0.75)
            .frame(maxWidth: .infinity)
            .frame(height: 64)
            .background(
                RoundedRectangle(cornerRadius: DS.rowRadius)
                    .fill(isCollected ? DS.card : Color.black.opacity(0.04))
            )
            .overlay(alignment: .bottomTrailing) {
                if isCollected {
                    Text(verbatim: "×\(count)")
                        .font(.system(size: 11, weight: .black, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(DS.primary))
                        .padding(4)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(isCollected ? Text(verbatim: "\(emoji) ×\(count)") : Text(verbatim: "?"))
    }
}
