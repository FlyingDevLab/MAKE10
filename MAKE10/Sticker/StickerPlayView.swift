//
//  StickerPlayView.swift
//  FDL-TenBlitz
//
//  Created by 空飛ぶ研究室(FlyingDevLab) on 2026/06/04.
//

// シール画面。お絵描きとシール配置を1つのキャンバスで遊ぶ。
// StickerStorageView から fullScreenCover で表示される。
//
// ★ 操作モデル ★
//   なぞる             → 線を描く（シールの上からでも描ける）
//   シールを長押し     → 掴んで動かせる。掴むと「選択中」になり下に編集バーが出る
//   選択中             → 描画は止まる。2本指ピンチで拡大縮小、回転で回る（場所はどこでもよい）
//   選択中にシール以外に触れる → 選択解除（編集バーの「できた」でも解除できる）
//   トレイをタップ     → ストレージのシールを中央付近へ追加
//   トレイを長押し     → ドラッグして好きな位置へ追加
//   シールをトレイへ   → ドラッグして離すとストレージへ戻る
//   トレイ右端のボタン → キャンバスのシールをぜんぶストレージへ戻す（確認あり）
//   道具パネルの つまみ → ドラッグで、パネルを好きな位置へ動かす
//   道具パネルの「ー」  → パネルを小さな 🎨 にたたむ（🎨 をタップで元に戻る。🎨 も動かせる）
//   ヘッダーの 🖼️       → いまの絵（線＋シール）を「かべがみ」にする（WallpaperStore を参照）
//
// ★ 道具パネルを動かせる・たためるようにしている理由 ★
//   色・ペン・シールの道具が画面の下にずっとあると、そこには描けない。
//   パネルを動かしたり 🎨 にたたんだりすれば、画面ぜんぶを使って描ける。
//   位置とたたんだかどうかは保存して、次に開いたときも同じにする。
//
// ★ ジェスチャー競合の解決方法 ★
//   描画（1本指ドラッグ）と2本指操作は、キャンバス全体（シールも含む親）に
//   simultaneousGesture で付けている。親の simultaneousGesture は子のシール上の
//   タッチも受け取れるため、シールの上をなぞればそのまま線が引ける。
//   シール側は「長押し → ドラッグ」だけを持つ。指がすぐ動けば長押しが失敗して
//   親の描画がそのまま続き、0.3秒止まれば掴める。掴んだ瞬間に、押した時点で
//   できてしまった点を cancelStroke() で消し、以降の描画入力は isGrabbing で無視する。
//
// ★ 選択解除の判定 ★
//   「シール以外に触れたら解除」は、キャンバスの描画ジェスチャーの onEnded で行う。
//   ただし同じタッチで「長押しで掴んだ」「2本指操作した」場合は解除してはいけないので、
//   それらが起きたら touchHandledByStickers を立て、onEnded で見てから戻す。
//
// ★ トレイからのドラッグを項目ではなく最上位で受けている理由 ★
//   ScrollView の中の項目に DragGesture（長押し後でも）を付けるとスクロールが効かなくなる。
//   そこで項目には長押し（onLongPressGesture）だけを付けて liftedEmoji を立て、
//   指の追従は最上位 ZStack の simultaneousGesture(DragGesture) で行う。
//   持ち上げている間は scrollDisabled でトレイのスクロールを止める。

import SwiftUI

// MARK: - 定数

private enum PlayC {
    static let baseFontSize: CGFloat = 40    // scale 1.0 のときのシールの大きさ ← 変更可
    static let minScale:     Double  = 0.5   // 最小倍率 ← 変更可
    static let maxScale:     Double  = 3.0   // 最大倍率 ← 変更可
    static let scaleStep:    Double  = 1.2   // 編集バーの ＋／－ 1回あたりの倍率 ← 変更可
    static let rotateStep:   Double  = 15    // 編集バーの ↻ 1回あたりの角度（度）← 変更可
    static let longPress:    Double  = 0.3   // 掴むまでの長押し時間（秒）← 変更可
    static let minHitSize:   CGFloat = 56    // シールの最小タッチ領域 ← 変更可
}

// MARK: - 下部バーの位置計測

// トレイ（ドロップ先）と下部バー全体（シールを隠さない範囲）の矩形を
// "playBoard" 座標系で親に伝えるための PreferenceKey
private struct FrameKey: PreferenceKey {
    static var defaultValue: [String: CGRect] = [:]
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue()) { $1 }
    }
}

// MARK: - StickerPlayView

struct StickerPlayView: View {
    @Environment(\.dismiss) private var dismiss
    private let store = StickerStore.shared

    @State private var drawingStore = DrawingStore.shared

    // 選択・操作状態
    @State private var selectedID:     UUID?   = nil     // 長押しで選んだシール
    @State private var isGrabbing:     Bool    = false   // シールを掴んで動かしている間 true
    @State private var isTransforming: Bool    = false   // 2本指操作の間 true
    @State private var touchHandledByStickers: Bool = false  // このタッチで掴み／2本指操作が起きた
    @State private var liveScale:      CGFloat = 1       // ピンチ中の相対倍率（確定前）
    @State private var liveRotation:   Angle   = .zero   // 回転中の相対角度（確定前）

    // トレイ関連
    @State private var isOverTray: Bool = false                       // シールをトレイの上まで運んでいる
    @State private var liftedEmoji: String?  = nil                    // トレイで長押しして持ち上げ中の絵文字
    @State private var lastTouch:   CGPoint? = nil                    // 最上位で追跡している指の位置
    @State private var trayGhost: (emoji: String, location: CGPoint)? = nil  // トレイから引き出し中の絵文字
    @State private var frames: [String: CGRect] = [:]                 // "tray" / "bottomBar"

    // トースト
    @State private var toastMessage: String? = nil

    // 背景色
    @State private var bgIndex: Int = UserDefaults.standard.integer(forKey: UDKey.playBoardBackground)
    @State private var showPalette: Bool = false

    // 道具パネル（動かす・たたむ）
    /// パネルを、いつもの位置（画面の下）から動かした量。保存しておき、次に開いたときも同じ位置にする。
    @State private var panelOffset = CGSize(
        width:  UserDefaults.standard.double(forKey: UDKey.playPanelOffsetX),
        height: UserDefaults.standard.double(forKey: UDKey.playPanelOffsetY)
    )
    /// つまみをドラッグしている最中の移動量（指を離したら panelOffset に足す）
    @State private var panelDrag: CGSize = .zero
    /// パネルを 🎨 にたたんでいるか
    @State private var isPanelCollapsed = UserDefaults.standard.bool(forKey: UDKey.playPanelCollapsed)

    // かべがみ
    @State private var showWallpaperConfirm = false
    @Environment(\.displayScale) private var displayScale

    // MARK: - パステルカラーパレット（10色）
    // インデックスが UDKey.playBoardBackground として保存される
    private let palette: [(name: String, color: Color)] = [
        ("White",     Color(red: 1.00, green: 1.00, blue: 1.00)), // #FFFFFF ← 変更可
        ("Cream",     Color(red: 1.00, green: 0.97, blue: 0.91)), // #FFF8E7 ← 変更可
        ("Pink",      Color(red: 1.00, green: 0.84, blue: 0.88)), // #FFD6E0 ← 変更可
        ("Peach",     Color(red: 1.00, green: 0.90, blue: 0.80)), // #FFE5CC ← 変更可
        ("Yellow",    Color(red: 1.00, green: 0.95, blue: 0.69)), // #FFF3B0 ← 変更可
        ("Green",     Color(red: 0.83, green: 0.96, blue: 0.83)), // #D4F5D4 ← 変更可
        ("Mint",      Color(red: 0.78, green: 0.94, blue: 0.91)), // #C8F0E8 ← 変更可
        ("Blue",      Color(red: 0.78, green: 0.88, blue: 1.00)), // #C8E0FF ← 変更可
        ("Lavender",  Color(red: 0.90, green: 0.83, blue: 1.00)), // #E5D4FF ← 変更可
        ("Gray",      Color(red: 0.91, green: 0.91, blue: 0.94)), // #E8E8F0 ← 変更可
    ]

    private var trayFrame:      CGRect { frames["tray"]      ?? .zero }
    private var bottomBarFrame: CGRect { frames["bottomBar"] ?? .zero }

    private var selectedSticker: StickerStore.Sticker? {
        guard let id = selectedID else { return nil }
        return store.playStickers.first { $0.id == id }
    }

    // MARK: - body

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .top) {
                // 背景色（全画面）
                palette[bgIndex].color

                // ── キャンバス（お絵描き＋シール）──
                ZStack {
                    DrawingCanvasView()

                    ForEach(store.playStickers) { sticker in
                        let selected = selectedID == sticker.id
                        PlayStickerView(
                            sticker:      sticker,
                            bounds:       geo.size,
                            isSelected:   selected,
                            liveScale:    selected ? liveScale    : 1,
                            liveRotation: selected ? liveRotation : .zero,
                            onGrab:        { grab(sticker.id) },
                            onDragChanged: { loc in isOverTray = trayFrame.contains(loc) },
                            onDragEnded:   { loc in drop(sticker: sticker, at: loc, bounds: geo.size) }
                        )
                    }

                    // トレイから引き出し中の絵文字（指に追従するゴースト）
                    if let ghost = trayGhost {
                        Text(ghost.emoji)
                            .font(.system(size: PlayC.baseFontSize * 1.3))
                            .shadow(color: .black.opacity(0.20), radius: 8, x: 0, y: 4)
                            .position(ghost.location)
                            .allowsHitTesting(false)
                    }
                }
                .contentShape(Rectangle())
                .simultaneousGesture(drawingGesture)
                .simultaneousGesture(transformGesture)

                // ── ヘッダー（常に最前面）──
                VStack {
                    headerBar
                        .padding(.top, 52)  // Safe Area 上端からの余白
                    Spacer()
                }

                // ── 道具パネル（動かせる・たためる）──
                VStack {
                    Spacer()
                    toolPanel(bounds: geo.size)
                        // ⚠️ 変更注意: frameReporter は padding と offset より内側に置くこと。
                        //   padding より内側 … まわりの余白を含まない、見えているパネルそのものの大きさになる
                        //   offset より内側 … 動かしたあとの位置が "bottomBar" として伝わる（トレイへのドロップ判定などに使う）
                        .background(frameReporter("bottomBar"))
                        .padding(.horizontal, 16)
                        .padding(.bottom, 24)  // Safe Area 下端からの余白 ← 変更可
                        .offset(x: panelOffset.width + panelDrag.width,
                                y: panelOffset.height + panelDrag.height)
                }
                .animation(.spring(response: 0.3, dampingFraction: 0.75), value: showPalette)
                .animation(.spring(response: 0.3, dampingFraction: 0.75), value: selectedID)
                .animation(.spring(response: 0.3, dampingFraction: 0.75), value: isPanelCollapsed)

                // トースト（満杯など）
                if let msg = toastMessage {
                    VStack {
                        Spacer()
                        Text(msg)
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 10)
                            .background(Capsule().fill(Color.black.opacity(0.72)))
                            .padding(.bottom, bottomBarFrame.height + 40)
                        }
                    .transition(.opacity.combined(with: .scale(scale: 0.9)))
                    .allowsHitTesting(false)
                }
            }
            .coordinateSpace(name: "playBoard")
            .simultaneousGesture(liftedDragGesture(bounds: geo.size))
            .onPreferenceChange(FrameKey.self) { frames = $0 }
            // パネルの大きさが変わったとき・画面の大きさが変わったときは、はみ出さないよう位置を直す
            .onChange(of: isPanelCollapsed) { _, _ in keepPanelOnScreen(bounds: geo.size, afterLayout: true) }
            .onChange(of: showPalette)      { _, _ in keepPanelOnScreen(bounds: geo.size, afterLayout: true) }
            .onChange(of: geo.size)         { _, size in keepPanelOnScreen(bounds: size, afterLayout: true) }
            .onAppear { keepPanelOnScreen(bounds: geo.size, afterLayout: true) }
            .alert("wallpaper_confirm_title", isPresented: $showWallpaperConfirm) {
                Button("wallpaper_confirm_ok") { makeWallpaper(size: geo.size) }
                Button("drawing_clear_cancel", role: .cancel) {}
            } message: {
                Text("wallpaper_confirm_message")
            }
        }
        .ignoresSafeArea()
    }

    // MARK: - 道具パネル

    /// 道具パネル。ひらいているときは つまみ・色・編集バー・ペン・シールのトレイ、たたんでいるときは 🎨 だけ。
    @ViewBuilder
    private func toolPanel(bounds: CGSize) -> some View {
        if isPanelCollapsed {
            Button {
                SoundManager.shared.vibrate()
                isPanelCollapsed = false
                UserDefaults.standard.set(false, forKey: UDKey.playPanelCollapsed)
            } label: {
                Text(verbatim: "🎨")
                    .font(.system(size: 30))
                    .frame(width: 60, height: 60)
                    .background(
                        Circle().fill(.white.opacity(0.9))
                            .shadow(color: .black.opacity(0.15), radius: 8, x: 0, y: 3)
                    )
            }
            .buttonStyle(.plain)
            .simultaneousGesture(panelDragGesture(bounds: bounds))
            .accessibilityLabel(Text("sticker_panel_expand"))
            .transition(.scale.combined(with: .opacity))
        } else {
            VStack(spacing: 10) {
                panelHandle(bounds: bounds)

                if showPalette {
                    paletteBar
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }

                // 編集バー（選択中のみ）・ツールバー・トレイ
                if let sticker = selectedSticker {
                    StickerEditBar(
                        sticker:   sticker,
                        onDone:    { deselect() },
                        onPutAway: { putAway(sticker.id) }
                    )
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }

                DrawingToolbarView()

                StickerTrayView(
                    isHighlighted: isOverTray,
                    liftedEmoji:   liftedEmoji,
                    onTap:         { emoji in addFromTray(emoji, at: nil, bounds: bounds) },
                    onLift:        { emoji in lift(emoji) },
                    onPutAwayAll:  { putAwayAll() }
                )
                .background(frameReporter("tray"))
            }
            .transition(.scale(scale: 0.6, anchor: .bottom).combined(with: .opacity))
        }
    }

    /// パネルの上の つまみ。ここをドラッグしてパネルを動かす。右の「ー」でたたむ。
    private func panelHandle(bounds: CGSize) -> some View {
        HStack {
            Color.clear.frame(width: 36, height: 36)   // 「ー」ボタンと左右の釣り合いをとる
            Spacer()
            Capsule()
                .fill(Color(.systemGray3))
                .frame(width: 56, height: 6)
            Spacer()
            Button {
                SoundManager.shared.vibrate()
                isPanelCollapsed = true
                UserDefaults.standard.set(true, forKey: UDKey.playPanelCollapsed)
            } label: {
                Image(systemName: "minus")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(Color(.darkGray))
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(.white.opacity(0.9)))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("sticker_panel_collapse"))
        }
        .padding(.horizontal, 6)
        .frame(height: 40)
        .background(
            Capsule().fill(.white.opacity(0.82))
                .shadow(color: .black.opacity(0.10), radius: 6, x: 0, y: 2)
        )
        .contentShape(Capsule())
        .gesture(panelDragGesture(bounds: bounds))
    }

    /// パネル（または 🎨）をドラッグで動かす。指を離したら、画面からはみ出さない位置に直して保存する。
    private func panelDragGesture(bounds: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 6, coordinateSpace: .named("playBoard"))
            .onChanged { value in
                panelDrag = value.translation
            }
            .onEnded { value in
                panelOffset = CGSize(width:  panelOffset.width  + value.translation.width,
                                     height: panelOffset.height + value.translation.height)
                panelDrag = .zero
                keepPanelOnScreen(bounds: bounds, afterLayout: true)
            }
    }

    /// パネルが画面からはみ出していたら、内側へ戻して位置を保存する。
    /// ヘッダー（戻るボタンなど）にはかぶらないよう、上は headerLimit までにする。
    /// - Parameter afterLayout: true なら、パネルの位置が画面に反映されてから（少し待ってから）直す
    private func keepPanelOnScreen(bounds: CGSize, afterLayout: Bool) {
        guard afterLayout else { return clampPanel(bounds: bounds) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { clampPanel(bounds: bounds) }
    }

    private func clampPanel(bounds: CGSize) {
        let f = bottomBarFrame
        guard f != .zero, bounds.width > 0 else { return }
        let margin:      CGFloat = 8     // ← 変更可（画面の端との すきま）
        let headerLimit: CGFloat = 100   // ← 変更可（これより上には行かない）
        var dx: CGFloat = 0, dy: CGFloat = 0
        if f.minX < margin                      { dx = margin - f.minX }
        else if f.maxX > bounds.width - margin  { dx = bounds.width - margin - f.maxX }
        if f.minY < headerLimit                 { dy = headerLimit - f.minY }
        else if f.maxY > bounds.height - margin { dy = bounds.height - margin - f.maxY }
        if dx != 0 || dy != 0 {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                panelOffset = CGSize(width: panelOffset.width + dx, height: panelOffset.height + dy)
            }
        }
        UserDefaults.standard.set(Double(panelOffset.width),  forKey: UDKey.playPanelOffsetX)
        UserDefaults.standard.set(Double(panelOffset.height), forKey: UDKey.playPanelOffsetY)
    }

    // MARK: - かべがみ

    /// いまの絵（背景の色・線・シール）を画像にして、かべがみにする。道具パネルやヘッダーは入れない。
    ///
    /// ★ ImageRenderer とは？ ★
    ///   SwiftUI のビューを、画面に出さずに画像（UIImage）として描いてくれる仕組み。
    ///   ここでは、キャンバスと同じものを「操作できない、ただの絵」として組み立てて画像にしている。
    private func makeWallpaper(size: CGSize) {
        let artwork = ZStack {
            palette[bgIndex].color
            DrawingCanvasView()
            ForEach(store.playStickers) { sticker in
                Text(sticker.emoji)
                    .font(.system(size: PlayC.baseFontSize * CGFloat(sticker.scale)))
                    .rotationEffect(.degrees(sticker.rotation))
                    .position(x: sticker.xRatio * size.width, y: sticker.yRatio * size.height)
            }
        }
        .frame(width: size.width, height: size.height)

        let renderer = ImageRenderer(content: artwork)
        renderer.scale = displayScale
        guard let image = renderer.uiImage else { return }
        WallpaperStore.shared.save(image)
        SoundManager.shared.playUnlock()
        showToast(String(localized: "wallpaper_done"))
    }

    /// 自分の矩形を "playBoard" 座標系で FrameKey に載せる透明ビュー
    private func frameReporter(_ key: String) -> some View {
        GeometryReader { g in
            Color.clear.preference(key: FrameKey.self, value: [key: g.frame(in: .named("playBoard"))])
        }
    }

    // MARK: - ジェスチャー（キャンバス全体）

    /// 1本指でなぞって線を描く。minimumDistance: 0 でタップ（点）も記録する。
    /// シール選択中・掴んでいる間・2本指操作中は描かない。
    /// 選択中にシール以外へ触れて離した場合は、ここで選択を解除する。
    private var drawingGesture: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named("playBoard"))
            .onChanged { value in
                guard selectedID == nil, !isGrabbing, !isTransforming else { return }
                let point = DrawingPoint(value.location)
                if drawingStore.activeStroke == nil {
                    drawingStore.beginStroke(at: point)
                } else {
                    drawingStore.continueStroke(to: point)
                }
            }
            .onEnded { _ in
                drawingStore.endStroke()
                let handled = touchHandledByStickers
                touchHandledByStickers = false
                // シール側の onEnded が来ない異常系（システム割り込み等）でも描画が止まらないよう保険で戻す
                isGrabbing = false
                if selectedID != nil && !handled {
                    deselect()
                }
            }
    }

    /// 選択中のシールに対する2本指ピンチ＋回転。画面のどこで行ってもよい。
    private var transformGesture: some Gesture {
        MagnifyGesture()
            .simultaneously(with: RotateGesture())
            .onChanged { value in
                guard selectedID != nil else { return }
                if !isTransforming {
                    isTransforming = true
                    touchHandledByStickers = true
                }
                liveScale    = value.first?.magnification ?? 1
                liveRotation = value.second?.rotation ?? .zero
            }
            .onEnded { _ in
                defer {
                    liveScale      = 1
                    liveRotation   = .zero
                    isTransforming = false
                }
                guard isTransforming, let sticker = selectedSticker else { return }
                store.updatePlayTransform(
                    id:       sticker.id,
                    scale:    clampScale(sticker.scale * Double(liveScale)),
                    rotation: sticker.rotation + liveRotation.degrees
                )
            }
    }

    /// 最上位で指の位置を追跡する。トレイで持ち上げた絵文字のゴースト表示と、
    /// 離した位置への配置に使う（詳細は冒頭コメント参照）。
    private func liftedDragGesture(bounds: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named("playBoard"))
            .onChanged { value in
                lastTouch = value.location
                if let emoji = liftedEmoji {
                    trayGhost = (emoji, value.location)
                }
            }
            .onEnded { value in
                if let emoji = liftedEmoji {
                    addFromTray(emoji, at: value.location, bounds: bounds)
                }
                liftedEmoji = nil
                trayGhost   = nil
                lastTouch   = nil
            }
    }

    // MARK: - シール操作

    /// トレイの項目を長押しで持ち上げた。以降の指の追従は liftedDragGesture が行う。
    private func lift(_ emoji: String) {
        liftedEmoji = emoji
        if let p = lastTouch { trayGhost = (emoji, p) }
        SoundManager.shared.vibrate()
    }

    private func putAwayAll() {
        store.moveAllPlayToStorage()
        selectedID = nil
        SoundManager.shared.vibrate()
    }

    private func grab(_ id: UUID) {
        drawingStore.cancelStroke()  // 押した瞬間にできた点を消す
        isGrabbing = true
        touchHandledByStickers = true
        selectedID = id
        store.bringPlayToFront(id: id)
        SoundManager.shared.vibrate()
    }

    /// シールを離したときの処理。location が nil なら動かさずに離した（選択だけ）。
    private func drop(sticker: StickerStore.Sticker, at location: CGPoint?, bounds: CGSize) {
        defer {
            isGrabbing = false
            isOverTray = false
        }
        guard let location else { return }

        if trayFrame.contains(location) {
            putAway(sticker.id)
            return
        }
        let p = clampedToCanvas(location, bounds: bounds)
        store.updatePlayPosition(
            id:     sticker.id,
            xRatio: p.x / bounds.width,
            yRatio: p.y / bounds.height
        )
    }

    private func putAway(_ id: UUID) {
        store.movePlayToStorage(id: id)
        selectedID = nil
        SoundManager.shared.vibrate()
    }

    private func deselect() {
        selectedID = nil
        SoundManager.shared.playTap()
    }

    /// トレイからの追加。location が nil ならタップ（螺旋自動配置）。
    private func addFromTray(_ emoji: String, at location: CGPoint?, bounds: CGSize) {
        if let location {
            // 道具パネルの上で離した場合は「やめた」とみなして何もしない
            guard !bottomBarFrame.contains(location) else { return }
        }
        guard !store.isPlayFull else {
            showToast(String(localized: "sticker_play_full"))
            return
        }
        if let location {
            let p = clampedToCanvas(location, bounds: bounds)
            store.moveStorageToPlay(emoji: emoji, xRatio: p.x / bounds.width, yRatio: p.y / bounds.height)
        } else {
            store.moveStorageToPlay(emoji: emoji)
        }
        SoundManager.shared.vibrate()
    }

    // MARK: - ヘルパー

    private func clampScale(_ s: Double) -> Double {
        max(PlayC.minScale, min(PlayC.maxScale, s))
    }

    /// キャンバス内（ヘッダーの下・画面の下の端より上）に収める。
    /// 道具パネルは動かせるので、パネルの下にも置ける（パネルを動かせば見える）。
    private func clampedToCanvas(_ point: CGPoint, bounds: CGSize) -> CGPoint {
        CGPoint(
            x: max(28, min(bounds.width - 28, point.x)),
            y: max(80, min(bounds.height - 40, point.y))
        )
    }

    private func showToast(_ msg: String) {
        SoundManager.shared.vibrate()
        withAnimation(.spring(response: 0.2)) { toastMessage = msg }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
            withAnimation { toastMessage = nil }
        }
    }

    // MARK: - ヘッダーバー

    // 戻るボタン・タイトル・パレットボタンを横並びにする。
    // 背景色が何色でも見えるよう、半透明白パネル＋ダーク固定でコントラストを確保する。
    private var headerBar: some View {
        HStack {
            Button {
                dismiss()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Color(.darkGray))
                    .frame(width: 40, height: 40)
                    .background(
                        Circle().fill(.white.opacity(0.75))
                            .shadow(color: .black.opacity(0.10), radius: 4, x: 0, y: 2)
                    )
            }
            .buttonStyle(.plain)

            Spacer()

            Text(LocalizedStringKey("game_picker_sticker"))
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundStyle(Color(.darkGray))
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(Capsule().fill(.white.opacity(0.75)))

            Spacer()

            // いまの絵を かべがみにする（確認してから）
            Button {
                SoundManager.shared.vibrate()
                showWallpaperConfirm = true
            } label: {
                Image(systemName: "photo.on.rectangle")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Color(.darkGray))
                    .frame(width: 40, height: 40)
                    .background(
                        Circle().fill(.white.opacity(0.75))
                            .shadow(color: .black.opacity(0.10), radius: 4, x: 0, y: 2)
                    )
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("wallpaper_button"))

            Button {
                withAnimation { showPalette.toggle() }
                SoundManager.shared.vibrate()
            } label: {
                Image(systemName: showPalette ? "paintpalette.fill" : "paintpalette")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(showPalette ? DS.primary : Color(.darkGray))
                    .frame(width: 40, height: 40)
                    .background(
                        Circle().fill(.white.opacity(0.75))
                            .shadow(color: .black.opacity(0.10), radius: 4, x: 0, y: 2)
                    )
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
    }

    // MARK: - パレットバー

    // 10色のカラーサークルを横並びで表示する。
    // 選択中は枠線と影で強調し、選択後すぐ UserDefaults に保存する。
    private var paletteBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(palette.indices, id: \.self) { i in
                    Button {
                        bgIndex = i
                        UserDefaults.standard.set(i, forKey: UDKey.playBoardBackground)
                        SoundManager.shared.vibrate()
                    } label: {
                        Circle()
                            .fill(palette[i].color)
                            .frame(width: 40, height: 40)
                            .overlay(
                                Circle()
                                    .strokeBorder(
                                        bgIndex == i ? DS.primary : Color(.systemGray4),
                                        lineWidth: bgIndex == i ? 3 : 1.5
                                    )
                            )
                            .shadow(
                                color: bgIndex == i ? DS.primary.opacity(0.35) : .black.opacity(0.08),
                                radius: bgIndex == i ? 6 : 3, x: 0, y: 2
                            )
                            .scaleEffect(bgIndex == i ? 1.15 : 1.0)
                            .animation(.spring(response: 0.2), value: bgIndex)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
        .background(
            RoundedRectangle(cornerRadius: 24)
                .fill(.white.opacity(0.82))
                .shadow(color: .black.opacity(0.10), radius: 10, x: 0, y: -3)
        )
    }
}

// MARK: - PlayStickerView（キャンバス上のシール1枚）

// 長押しで掴み、そのままドラッグして動かす。
// 表示倍率・回転は保存値に「操作中の相対値（liveScale / liveRotation）」を掛け合わせる。
private struct PlayStickerView: View {
    let sticker:      StickerStore.Sticker
    let bounds:       CGSize
    let isSelected:   Bool
    let liveScale:    CGFloat
    let liveRotation: Angle
    let onGrab:        () -> Void
    let onDragChanged: (CGPoint) -> Void
    let onDragEnded:   (CGPoint?) -> Void   // nil = 動かさずに離した

    @State private var livePosition: CGPoint? = nil
    @State private var isHeld: Bool = false

    private var storedPosition: CGPoint {
        CGPoint(x: sticker.xRatio * bounds.width, y: sticker.yRatio * bounds.height)
    }
    private var scale: CGFloat { CGFloat(sticker.scale) * liveScale }
    private var hitSize: CGFloat { max(PlayC.minHitSize, PlayC.baseFontSize * 1.2 * scale) }

    var body: some View {
        ZStack {
            if isSelected {
                Circle()
                    .fill(DS.primary.opacity(0.10))
                    .overlay(Circle().strokeBorder(DS.primary, lineWidth: 2.5))
            }
            Text(sticker.emoji)
                .font(.system(size: PlayC.baseFontSize * scale))
                .rotationEffect(.degrees(sticker.rotation + liveRotation.degrees))
        }
        .frame(width: hitSize, height: hitSize)
        .contentShape(Circle())
        .scaleEffect(isHeld ? 1.30 : 1.0)
        .shadow(color: isHeld ? .black.opacity(0.20) : .clear, radius: 8, x: 0, y: 4)
        .animation(.spring(response: 0.22, dampingFraction: 0.55), value: isHeld)
        .position(livePosition ?? storedPosition)
        .gesture(grabGesture)
    }

    /// 長押し（0.3秒）→ ドラッグ。長押しが成立する前に指が動けば失敗し、
    /// 親の描画ジェスチャーがそのまま線を引く。
    private var grabGesture: some Gesture {
        LongPressGesture(minimumDuration: PlayC.longPress)
            .sequenced(before: DragGesture(minimumDistance: 0, coordinateSpace: .named("playBoard")))
            .onChanged { value in
                guard case .second(true, let drag) = value else { return }
                if !isHeld {
                    isHeld = true
                    onGrab()
                }
                if let drag {
                    livePosition = drag.location
                    onDragChanged(drag.location)
                }
            }
            .onEnded { value in
                if case .second(true, let drag) = value {
                    onDragEnded(drag?.location)
                }
                livePosition = nil
                isHeld       = false
            }
    }
}

// MARK: - StickerEditBar（選択中のシールの編集バー）

private struct StickerEditBar: View {
    let sticker:   StickerStore.Sticker
    let onDone:    () -> Void
    let onPutAway: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            editButton("plus.magnifyingglass", "sticker_edit_bigger") {
                setTransform(scale: sticker.scale * PlayC.scaleStep)
            }
            editButton("minus.magnifyingglass", "sticker_edit_smaller") {
                setTransform(scale: sticker.scale / PlayC.scaleStep)
            }
            editButton("rotate.right", "sticker_edit_rotate") {
                setTransform(rotation: sticker.rotation + PlayC.rotateStep)
            }
            editButton("tray.and.arrow.down", "sticker_edit_put_away", action: onPutAway)

            Spacer(minLength: 4)

            Button(action: onDone) {
                Text("sticker_edit_done")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Capsule().fill(DS.primary))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: DS.chipRadius))
    }

    private func setTransform(scale: Double? = nil, rotation: Double? = nil) {
        let s = max(PlayC.minScale, min(PlayC.maxScale, scale ?? sticker.scale))
        StickerStore.shared.updatePlayTransform(
            id:       sticker.id,
            scale:    s,
            rotation: rotation ?? sticker.rotation
        )
        SoundManager.shared.vibrate()
    }

    private func editButton(_ symbol: String, _ labelKey: LocalizedStringKey,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Image(systemName: symbol)
                    .font(.system(size: 18, weight: .semibold))
                Text(labelKey)
                    .font(.system(size: 9, weight: .medium))
            }
            .foregroundStyle(DS.textBody)
            .frame(minWidth: 48, minHeight: 44)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - StickerTrayView（ストレージのシールを並べた下部トレイ）

// タップで追加（自動配置）、長押しで持ち上げてから好きな位置へ追加。
// キャンバスのシールをこの上まで運んで離すとストレージへ戻る（isHighlighted で強調）。
// 右端の「ぜんぶしまう」でキャンバスのシールをまとめてストレージへ戻す。
private struct StickerTrayView: View {
    let isHighlighted: Bool
    let liftedEmoji:   String?
    let onTap:         (String) -> Void
    let onLift:        (String) -> Void
    let onPutAwayAll:  () -> Void

    @State private var showPutAwayAllAlert = false

    private let store = StickerStore.shared
    private var groups: [StickerStore.EmojiGroup] { StickerStore.grouped(store.storageEmojis) }

    var body: some View {
        HStack(spacing: 0) {
            ZStack {
                if groups.isEmpty {
                    Text("sticker_tray_empty")
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(DS.muted)
                        .frame(maxWidth: .infinity)
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(groups) { group in
                                TrayItemView(
                                    group:     group,
                                    isLifting: liftedEmoji == group.emoji,
                                    onTap:     { onTap(group.emoji) },
                                    onLift:    { onLift(group.emoji) }
                                )
                            }
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                    }
                    // 持ち上げている間はスクロールを止め、指の移動をゴーストの追従に専念させる
                    .scrollDisabled(liftedEmoji != nil)
                }

                if isHighlighted {
                    Text("sticker_tray_drop_here")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(DS.primary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(RoundedRectangle(cornerRadius: DS.chipRadius).fill(DS.primary.opacity(0.15)))
                }
            }

            Divider()
                .frame(height: 40)

            putAwayAllButton
                .padding(.horizontal, 6)
        }
        .frame(height: 72)
        .frame(maxWidth: .infinity)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: DS.chipRadius))
        .overlay(
            RoundedRectangle(cornerRadius: DS.chipRadius)
                .strokeBorder(isHighlighted ? DS.primary : Color.clear, lineWidth: 2)
        )
        .animation(.easeInOut(duration: 0.15), value: isHighlighted)
        .alert(
            String(localized: "sticker_put_away_all_alert_title"),
            isPresented: $showPutAwayAllAlert
        ) {
            Button(String(localized: "sticker_edit_put_away"), role: .destructive) {
                onPutAwayAll()
            }
            Button(String(localized: "drawing_clear_cancel"), role: .cancel) {}
        } message: {
            Text("sticker_put_away_all_alert_message")
        }
    }

    /// キャンバスのシールをまとめてストレージへ戻すボタン。キャンバスが空なら薄くして無効化。
    private var putAwayAllButton: some View {
        Button {
            showPutAwayAllAlert = true
        } label: {
            VStack(spacing: 2) {
                Image(systemName: "tray.full")
                    .font(.system(size: 18, weight: .semibold))
                Text("sticker_put_away_all")
                    .font(.system(size: 9, weight: .medium))
            }
            .foregroundStyle(DS.textBody)
            .frame(minWidth: 52, minHeight: 44)
            .opacity(store.playStickers.isEmpty ? 0.35 : 1.0)
        }
        .buttonStyle(.plain)
        .disabled(store.playStickers.isEmpty)
        .accessibilityLabel(String(localized: "sticker_put_away_all"))
    }
}

// MARK: - TrayItemView（トレイの1項目：絵文字＋×N）

// ジェスチャーはタップと長押しだけ。ドラッグの追従は StickerPlayView 側で行う
// （項目に DragGesture を付けると ScrollView のスクロールが効かなくなるため）。
private struct TrayItemView: View {
    let group:     StickerStore.EmojiGroup
    let isLifting: Bool
    let onTap:     () -> Void
    let onLift:    () -> Void

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Text(group.emoji)
                .font(.system(size: 34))
                .frame(width: 52, height: 52)
                .opacity(isLifting ? 0.35 : 1.0)

            Text("×\(group.count)")
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(Capsule().fill(DS.primary))
                .offset(x: 4, y: 2)
        }
        .contentShape(Rectangle())
        .onTapGesture { onTap() }
        .onLongPressGesture(minimumDuration: PlayC.longPress) { onLift() }
    }
}
