//
//  StickerDexView.swift
//  FDL-TenBlitz
//
//  Created by 空飛ぶ研究室(FlyingDevLab) on 2026/10/02.
//
//  シールじてん。手に入るシールの全種類をカテゴリごとに並べ、
//  手に入れたシールは持っている枚数と一緒に、まだのシールは黒いシルエットで見せる。
//
//  開き方は3つ（v1.6.0 から）:
//    ・タイトル画面の「シールじてん」タイル … ゲームと同じく共通の枠（SharedFrame）の中に出す（isEmbedded = true）
//    ・シール帳の「シールじてん」ボタン     … シートで出す（isEmbedded = false。とじるボタンつき）
//    ・シールやさんの「シールじてん」ボタン … シートで出す（同上）
//
//  役割分担:
//    - StickerDexView（このファイル）: 一覧の表示（見るだけ。シールを動かす操作はない）
//    - StickerCatalog                : どんなシールがあるか（カテゴリと並び順）
//    - StickerStore                  : いま持っている枚数（ownedCounts）
//
//  ★ 「見つけた」かどうかの決め方（v1.6.0 から）★
//    シールをエネルギーに交換して0枚にできるようになったので、「持っている枚数」ではなく
//    「一度でも手に入れたか」（StickerStore.discovered）で決める。0枚にしても黒いシルエットに戻らない。
//
//  ★ エネルギーへの交換（v1.6.0 から）★
//    ・シールを押すと、そのシールのカードが開く。つかっていない枚数・ぜんぶの枚数を見て、
//      「1まい こうかん」したり、「ガチャで でたら じどうで こうかん」をオン／オフしたりできる
//    ・上の「つかっていない シールを ぜんぶ こうかん」で、つかっていないシールをまとめて交換する（確かめの画面あり）
//    ・交換して0枚になった種類があれば、「これから じどうで こうかん する？」と聞く
//    ゲーム画面やシール帳に貼ってあるシールは、作品をこわさないよう交換しない（StickerStore 冒頭を参照）。
//
//  ★ このファイルの構成 ★
//    StickerDexView … 画面本体（あつめた数・カテゴリごとの一覧・とじるボタン）
//    StickerDexCell … 一覧の1マス（シール1種類分）

import SwiftUI

// MARK: - StickerDexView

struct StickerDexView: View {

    // MARK: 依存

    @Environment(\.dismiss) private var dismiss

    /// 共通の枠（SharedFrame）の中に出すか。true のときは、枠のヘッダーにタイトルと戻るボタンがあるので、
    /// この画面のタイトルと「とじる」ボタンは出さず、一覧を紙のカードにのせる（かべがみの上でも読めるように）。
    var isEmbedded: Bool = false

    // MARK: 表示用の値

    private let store = StickerStore.shared

    /// シールの種類ごとの所有数（ゲーム画面・シール帳・ストレージの合計）。
    /// 交換すると変わるので、そのつど数え直す（StickerStore は @Observable なので、変わると描き直される）。
    private var owned: [String: Int] { store.ownedCounts() }

    /// あつめた種類の数（全シールのうち、一度でも手に入れたもの）。
    private var collectedCount: Int {
        StickerCatalog.all.filter { store.isDiscovered($0) }.count
    }

    // MARK: 交換の画面の状態

    /// カードを開いているシール（nil なら閉じている）。
    @State private var selectedEmoji: String? = nil
    /// 「つかっていない シールを ぜんぶ こうかん」の確かめを出しているか。
    @State private var showExchangeAllConfirm = false
    /// 交換して0枚になり、「これから じどうで こうかん する？」と聞いている種類（空なら聞いていない）。
    @State private var askAutoFor: [String] = []
    /// 交換したあとに一瞬出す「🔥 +30」（nil なら出さない）。
    @State private var gainedKcal: Double? = nil

    // MARK: body

    var body: some View {
        Group {
            if isEmbedded {
                dexContent
                    .clipShape(RoundedRectangle(cornerRadius: DS.cardRadius))
                    .background(
                        RoundedRectangle(cornerRadius: DS.cardRadius)
                            .fill(DS.bg)
                            .shadow(color: .black.opacity(0.10), radius: 12, x: 0, y: 4)
                    )
                    .padding(.horizontal, 12)
                    // ヘッダーの下にぶら下がるエネルギー残高と重ならないよう、少し下げる
                    .padding(.top, 20)   // ← 変更可
                    .padding(.bottom, 8)
            } else {
                dexContent
                    .background(DS.bg.ignoresSafeArea())
            }
        }
        // ★ overlay で重ねる理由 ★
        //   ZStack に並べると、カードが画面より高いとき（iPhone の横向きなど）に画面全体の大きさが
        //   カードに引っぱられ、上の帯まで押し上げられてしまった。overlay は「重ねるだけ」で
        //   もとの画面の大きさを変えないので、一覧の並びはそのまま、カードだけが上にのる。
        .overlay { ZStack { exchangeOverlays } }
        .animation(.easeInOut(duration: 0.2), value: selectedEmoji)
        .animation(.easeInOut(duration: 0.2), value: showExchangeAllConfirm)
        .animation(.easeInOut(duration: 0.2), value: askAutoFor)
        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: gainedKcal)
    }

    /// あつめた数と、カテゴリごとの一覧。
    private var dexContent: some View {
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
                                    let found = store.isDiscovered(emoji)
                                    StickerDexCell(emoji: emoji, count: owned[emoji, default: 0],
                                                   isCollected: found, isAuto: store.autoExchange.contains(emoji))
                                        // 見つけたシールだけ押せる（まだのシールは、何もしない）
                                        .onTapGesture {
                                            guard found else { return }
                                            SoundManager.shared.playTap()
                                            selectedEmoji = emoji
                                        }
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
    }

    // MARK: サブビュー

    /// 上の帯：タイトル・あつめた数・とじるボタン。
    private var header: some View {
        VStack(spacing: 10) {
            // 共通の枠の中に出すときは、枠のヘッダーにタイトルと戻るボタンがあるので出さない
            if !isEmbedded {
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

            exchangeAllButton
        }
        .padding(.horizontal, 20)
        .padding(.top, 20)
        .padding(.bottom, 12)
    }

    /// カテゴリの見出し。そのカテゴリで何種類あつめたかも出す。
    private func categoryHeader(_ category: StickerCatalog.Category) -> some View {
        let got = category.emojis.filter { store.isDiscovered($0) }.count
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

// MARK: - エネルギーへの交換

extension StickerDexView {

    /// 「つかっていない シールを ぜんぶ こうかん」ボタン（つかっていないシールがあるときだけ押せる）。
    var exchangeAllButton: some View {
        let count = store.unusedTotal
        let kcal  = StickerExchangeTuning.kcal(for: store.storageEmojis)
        return Button {
            SoundManager.shared.playTap()
            showExchangeAllConfirm = true
        } label: {
            HStack(spacing: 6) {
                Text(verbatim: "🔥")
                Text("sticker_exchange_all_button \(count) \(EnergyStore.format(kcal))")
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
            }
            .font(.system(size: 14, weight: .bold, design: .rounded))
            .foregroundStyle(count > 0 ? DS.energy : DS.muted)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 9)
            .background(Capsule().fill((count > 0 ? DS.energy : DS.muted).opacity(0.10)))
        }
        .buttonStyle(.plain)
        .disabled(count == 0)
    }

    /// 交換のカード・確かめ・自動交換の質問・「🔥 +30」を、一覧の上に重ねて出す。
    @ViewBuilder
    var exchangeOverlays: some View {
        if let emoji = selectedEmoji {
            dimmed { selectedEmoji = nil }
            StickerExchangeCard(
                emoji:     emoji,
                unused:    store.unusedCount(of: emoji),
                total:     owned[emoji, default: 0],
                isAuto:    store.autoExchange.contains(emoji),
                onExchange: { exchangeOne(emoji) },
                onToggleAuto: { on in store.setAutoExchange(on, for: [emoji]) },
                onClose:   { selectedEmoji = nil }
            )
            .transition(.scale(scale: 0.9).combined(with: .opacity))
        }
        if showExchangeAllConfirm {
            dimmed { showExchangeAllConfirm = false }
            confirmCard(
                title:   "sticker_exchange_all_title",
                body:    Text("sticker_exchange_all_body \(store.unusedTotal) \(EnergyStore.format(StickerExchangeTuning.kcal(for: store.storageEmojis)))"),
                yes:     "sticker_exchange_all_ok",
                no:      "reset_confirm_cancel",
                onYes:   { exchangeAll() },
                onNo:    { showExchangeAllConfirm = false }
            )
        }
        if !askAutoFor.isEmpty {
            dimmed { askAutoFor = [] }
            confirmCard(
                title:   "sticker_auto_ask_title",
                body:    Text("sticker_auto_ask_body \(askAutoFor.joined(separator: " "))"),
                yes:     "sticker_auto_ask_yes",
                no:      "sticker_auto_ask_no",
                onYes:   { store.setAutoExchange(true, for: askAutoFor); askAutoFor = [] },
                onNo:    { askAutoFor = [] }
            )
        }
        if let kcal = gainedKcal {
            Text(verbatim: "🔥 +\(EnergyStore.format(kcal))kcal")
                .font(.system(size: 26, weight: .black, design: .rounded))
                .foregroundStyle(DS.energy)
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .background(Capsule().fill(DS.card).shadow(color: DS.energy.opacity(0.25), radius: 10))
                .transition(.scale(scale: 0.6).combined(with: .opacity))
                .allowsHitTesting(false)
        }
    }

    // MARK: 交換の処理

    private func exchangeOne(_ emoji: String) {
        let kcal = store.exchangeOne(emoji)
        guard kcal > 0 else { return }
        showGain(kcal)
        // 交換して0枚になったら（自動交換がまだオフなら）、これから自動で交換するか聞く
        if store.isEmpty(emoji) && !store.autoExchange.contains(emoji) {
            selectedEmoji = nil
            askAutoFor = [emoji]
        }
    }

    private func exchangeAll() {
        showExchangeAllConfirm = false
        let result = store.exchangeAllUnused()
        guard result.count > 0 else { return }
        showGain(result.kcal)
        if !result.emptied.isEmpty { askAutoFor = result.emptied }
    }

    /// 「🔥 +30kcal」を一瞬出して、振動で「エネルギーに なった」ことを手にも伝える。
    private func showGain(_ kcal: Double) {
        SoundManager.shared.playCoinLand()
        SoundManager.shared.vibrate()
        gainedKcal = kcal
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { gainedKcal = nil }   // ← 変更可（出している時間）
    }

    // MARK: 重ねる部品

    /// 後ろを暗くする幕。押すと閉じる。
    private func dimmed(_ onTap: @escaping () -> Void) -> some View {
        Color.black.opacity(0.30)
            .ignoresSafeArea()
            .onTapGesture(perform: onTap)
            .transition(.opacity)
    }

    /// 「はい／いいえ」の確かめのカード（まとめて交換・自動交換の質問）。
    private func confirmCard(title: LocalizedStringKey, body: Text, yes: LocalizedStringKey, no: LocalizedStringKey,
                             onYes: @escaping () -> Void, onNo: @escaping () -> Void) -> some View {
        VStack(spacing: 16) {
            Text(title)
                .font(.system(size: 19, weight: .bold, design: .rounded))
                .foregroundStyle(DS.primary)
                .multilineTextAlignment(.center)
            body
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .foregroundStyle(DS.textDialog)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 12) {
                Button(action: onNo) {
                    Text(no)
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundStyle(DS.muted)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                        .background(RoundedRectangle(cornerRadius: DS.btnRadius).fill(Color.black.opacity(0.05)))
                }
                .buttonStyle(.plain)
                Button(action: onYes) {
                    Text(yes)
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                        .background(RoundedRectangle(cornerRadius: DS.btnRadius).fill(DS.energy))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(24)
        .frame(maxWidth: 360)
        .background(
            RoundedRectangle(cornerRadius: DS.sheetRadius)
                .fill(DS.card)
                .shadow(color: .black.opacity(0.12), radius: 20, x: 0, y: 8)
        )
        .padding(.horizontal, 32)
        .transition(.scale(scale: 0.9).combined(with: .opacity))
    }
}

// MARK: - StickerExchangeCard

/// シール1種類のカード。枚数を見せ、1枚交換と、自動交換のオン／オフができる。
private struct StickerExchangeCard: View {
    let emoji:  String
    /// つかっていない枚数（交換できる枚数）
    let unused: Int
    /// ぜんぶの枚数（貼ってある分も入れる）
    let total:  Int
    let isAuto: Bool
    let onExchange:   () -> Void
    let onToggleAuto: (Bool) -> Void
    let onClose:      () -> Void

    var body: some View {
        // 収まるときはそのまま、収まらないとき（iPhone の横向きなど）はカードの中をスクロールする（設定画面と同じ）
        ViewThatFits(in: .vertical) {
            content
            ScrollView { content }
                .scrollBounceBehavior(.basedOnSize)
        }
        .frame(maxWidth: 340)
        .background(
            RoundedRectangle(cornerRadius: DS.sheetRadius)
                .fill(DS.card)
                .shadow(color: .black.opacity(0.12), radius: 20, x: 0, y: 8)
        )
        .clipShape(RoundedRectangle(cornerRadius: DS.sheetRadius))
        .padding(.horizontal, 32)
        .padding(.vertical, 12)
    }

    private var content: some View {
        VStack(spacing: 14) {
            Text(emoji)
                .font(.system(size: 72))
            // ★ 「2 / 3」のような分数にしない理由 ★
            //   子どもが「3つのうち2つめ」や分数と読み違えないよう、ことばで「つかっていない」「ぜんぶ」と分けて書く。
            Text("sticker_exchange_counts \(unused) \(total)")
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundStyle(DS.textBody)
                .multilineTextAlignment(.center)

            Button(action: onExchange) {
                // 星座と 🍪 は、ほかのシールより多くもらえる（StickerExchangeTuning を参照）
                Text("sticker_exchange_one_button \(EnergyStore.format(StickerExchangeTuning.kcal(for: emoji)))")
                    .font(.system(size: 17, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(RoundedRectangle(cornerRadius: DS.btnRadius).fill(unused > 0 ? DS.energy : DS.muted.opacity(0.35)))
            }
            .buttonStyle(.plain)
            .disabled(unused == 0)

            if unused == 0 && total > 0 {
                // 貼ってあるシールしかないときは、なぜ押せないかを伝える
                Text("sticker_exchange_only_used")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(DS.muted)
                    .multilineTextAlignment(.center)
            }

            Toggle(isOn: Binding(get: { isAuto }, set: { onToggleAuto($0) })) {
                Text("sticker_auto_toggle")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(DS.textBody)
            }
            .tint(DS.energy)

            Button(action: onClose) {
                Text("settings_close_button")
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(DS.muted)
                    .padding(.horizontal, 30)
                    .padding(.vertical, 10)
                    .background(Capsule().fill(Color.black.opacity(0.05)))
            }
            .buttonStyle(.plain)
        }
        .padding(24)
    }
}

// MARK: - StickerDexCell

/// じてんの1マス。手に入れたシールは色つきで枚数を、まだのシールは黒いシルエットで出す。
private struct StickerDexCell: View {
    let emoji: String
    let count: Int
    /// 一度でも手に入れたか（0枚でも true のことがある。StickerStore.discovered を参照）
    let isCollected: Bool
    /// ガチャで出たら自動でエネルギーに交換する種類か（右上に 🔥 を出す）
    let isAuto: Bool

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
            .overlay(alignment: .topTrailing) {
                if isAuto {
                    Text(verbatim: "🔥")
                        .font(.system(size: 12))
                        .padding(3)
                }
            }
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
