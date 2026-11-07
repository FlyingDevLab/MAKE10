//
//  CustomStickerMakerView.swift
//  FDL-TenBlitz
//
//  Created by 空飛ぶ研究室(FlyingDevLab) on 2026/11/07.
//
//  オリジナルシールを作る画面。白い紙に描くか、カメラで撮った写真の上に描く。
//  シールじてんのオリジナルの欄から開く。
//
//  ★ このファイルの構成 ★
//    CustomStickerArt       … シールの絵（画面の表示と、保存する画像の両方で同じものを使う）
//    TransparencyChecker    … 透明なところに敷く市松模様（画面の表示だけ）
//    CustomStickerMakerView … 画面本体（紙・道具・名前・つくるボタン）
//
//  ★ 背景を透明にする ★
//    手描きは白い台紙とふちをなくし、描いた線だけをシールにする。
//    写真は写っている人や物だけを切り抜く（StickerCutout.swift を参照）。
//    紙の後ろの市松模様は「ここは透明」と見せるためのもので、シールの画像には入らない。
//
//  ★ 消しゴムで写真は消えない ★
//    写真と線は別の層にしてあり、消しゴムの「透明な穴」は線の層だけに開く。
//    そのため、消しゴムで消えるのは描いた線だけで、写真はそのまま残る。

import SwiftUI

// MARK: - CustomStickerArt

/// シールの絵。角の丸い台紙に、写真と線を重ねる。背景が透明のときは、台紙とふちを付けない。
struct CustomStickerArt: View {
    let photo:   UIImage?
    let strokes: [DrawingStroke]
    let side:    CGFloat
    var isTransparent = false

    /// 角の丸みとふちの太さ（1辺に対する割合）。
    private static let cornerRatio: CGFloat = 0.12   // ← 変更可
    private static let borderRatio: CGFloat = 0.03   // ← 変更可

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: isTransparent ? 0 : side * Self.cornerRatio)
        ZStack {
            if !isTransparent {
                Color.white
            }
            if let photo {
                Image(uiImage: photo)
                    .resizable()
                    .scaledToFill()
                    .frame(width: side, height: side)
                    .clipped()
            }
            StrokeLayer(strokes: strokes, paperSize: CGSize(width: side, height: side))
        }
        .frame(width: side, height: side)
        .clipShape(shape)
        // シールらしく、白いふちで囲む
        .overlay(shape.strokeBorder(Color.white, lineWidth: isTransparent ? 0 : side * Self.borderRatio))
    }
}

// MARK: - TransparencyChecker

/// 透明なところに敷く、灰色と白の市松模様。
private struct TransparencyChecker: View {
    private static let cell: CGFloat = 16   // ← 変更可（マスの大きさ）

    var body: some View {
        Canvas { context, size in
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.white))
            let columns = Int(size.width / Self.cell) + 1
            let rows    = Int(size.height / Self.cell) + 1
            for row in 0..<rows {
                for column in 0..<columns where (row + column).isMultiple(of: 2) {
                    let rect = CGRect(x: CGFloat(column) * Self.cell, y: CGFloat(row) * Self.cell,
                                      width: Self.cell, height: Self.cell)
                    context.fill(Path(rect), with: .color(Color.black.opacity(0.08)))
                }
            }
        }
    }
}

// MARK: - CustomStickerMakerView

struct CustomStickerMakerView: View {

    @Environment(\.dismiss) private var dismiss
    @Environment(\.displayScale) private var displayScale

    private let customStore = CustomStickerStore.shared
    private let energy      = EnergyStore.shared

    // MARK: 紙の状態

    @State private var photo: UIImage? = nil
    /// 背景を透明にした写真（isTransparent のときに作る）
    @State private var cutout: UIImage? = nil
    /// 背景を透明にするか
    @State private var isTransparent = false
    @State private var strokes: [DrawingStroke] = []
    /// 指で描いている途中の線（指を離すと strokes に入る）
    @State private var activeStroke: DrawingStroke? = nil
    /// 指で描いている途中か。
    /// ★ @GestureState を使う理由 ★
    ///   スクロールなどに指の動きを取られると、onEnded は呼ばれずにジェスチャーが終わる。
    ///   @GestureState は、どんな終わり方でも元の値に戻るので、これを見て線を確定する。
    ///   onEnded で確定すると、描きかけの線が残って次の線とつながってしまう。
    @GestureState private var isDrawing = false

    // MARK: 道具の状態

    @State private var colorHex  = DrawingColor.palette.first?.hex ?? "#FF3B30"
    @State private var isEraser  = false
    @State private var lineWidth = Self.lineWidths[1]
    @State private var name      = ""

    // MARK: 画面の状態

    @State private var showCamera        = false
    @State private var showCameraDenied  = false
    @State private var showCreateConfirm = false
    @State private var showLeaveConfirm  = false
    @State private var showCutoutFailed  = false

    /// 線の太さ（紙の幅に対する割合）。← 変更可
    private static let lineWidths: [CGFloat] = [0.02, 0.04, 0.08]
    /// 紙の1辺の範囲（pt）。横向きの iPhone でも描ける大きさは保ち、入らない分はスクロールする。
    private static let paperSideRange: ClosedRange<CGFloat> = 240...520   // ← 変更可
    /// 写真を手元に持っておくときの長い辺（px）。撮ったままの大きさだとメモリを使いすぎる。
    private static let maxPhotoSide: CGFloat = 1_024   // ← 変更可

    /// 消しゴムの線しかなくても「何か描いた」とは言えないので、色の線か写真があるときだけ作れる。
    /// 写真を切り抜いている途中か（切り抜きの途中は、透明のボタンを押せない）。
    private var isCuttingOut: Bool { isTransparent && photo != nil && cutout == nil }
    private var hasContent: Bool { photo != nil || strokes.contains { !$0.isEraser } }
    private var hasUnsavedWork: Bool { photo != nil || !strokes.isEmpty }

    private var price: Double { customStore.nextPrice }
    private var canAfford: Bool { energy.canAfford(price) }

    // MARK: body

    var body: some View {
        GeometryReader { geo in
            ScrollView {
                VStack(spacing: 14) {
                    paper(side: paperSide(in: geo.size))
                    ViewThatFits {
                        HStack(spacing: 10) { photoButton; transparentButton }
                        VStack(spacing: 8) { photoButton; transparentButton }
                    }
                    toolRow
                    palette
                    nameField
                    makeButton
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
                .frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively)
            .safeAreaInset(edge: .top, spacing: 0) { header }
        }
        .background(DS.bg.ignoresSafeArea())
        .fullScreenCover(isPresented: $showCamera) {
            CameraPicker { image in
                setPhoto(Self.shrunk(image))
            }
            .ignoresSafeArea()
        }
        .alert(Text("sticker_custom_camera_denied_title"), isPresented: $showCameraDenied) {
            Button("settings_close_button", role: .cancel) {}
        } message: {
            Text("sticker_custom_camera_denied_body")
        }
        .alert(Text("sticker_custom_cutout_failed_title"), isPresented: $showCutoutFailed) {
            Button("settings_close_button", role: .cancel) {}
        } message: {
            Text("sticker_custom_cutout_failed_body")
        }
        .alert(Text("sticker_custom_leave_title"), isPresented: $showLeaveConfirm) {
            Button("reset_confirm_cancel", role: .cancel) {}
            Button("sticker_custom_leave_ok", role: .destructive) { dismiss() }
        }
        .alert(Text("sticker_custom_confirm_title"), isPresented: $showCreateConfirm) {
            Button("reset_confirm_cancel", role: .cancel) {}
            Button("sticker_custom_confirm_ok") { create() }
        } message: {
            Text("sticker_custom_confirm_body \(EnergyStore.format(price))")
        }
    }

    private func paperSide(in size: CGSize) -> CGFloat {
        let wanted = min(size.width - 32, size.height - 380)
        return min(max(wanted, Self.paperSideRange.lowerBound), Self.paperSideRange.upperBound)
    }

    // MARK: サブビュー

    private var header: some View {
        HStack {
            Text("sticker_custom_make_title")
                .font(.system(size: 22, weight: .black, design: .rounded))
                .foregroundStyle(DS.primary)
            Spacer()
            EnergyBadge(showsLabel: false, fontSize: 18)
            StickerCloseButton {
                if hasUnsavedWork {
                    showLeaveConfirm = true
                } else {
                    dismiss()
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(DS.bg)
    }

    /// 紙。指でなぞると線が描ける。
    private func paper(side: CGFloat) -> some View {
        CustomStickerArt(photo: displayedPhoto,
                         strokes: strokes + (activeStroke.map { [$0] } ?? []),
                         side: side,
                         isTransparent: isTransparent)
            .background { if isTransparent { TransparencyChecker() } }
            .overlay { if isCuttingOut { ProgressView().controlSize(.large) } }
            .compositingGroup()   // 影が内側のふちにも付かないよう、1枚にまとめてから影を付ける
            .shadow(color: .black.opacity(0.15), radius: 8, x: 0, y: 3)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .updating($isDrawing) { _, state, _ in state = true }
                    .onChanged { drag in
                        // 紙の外まで指が動いても、線は紙のふちにとどめる
                        let point = DrawingPoint(CGPoint(x: min(max(drag.location.x / side, 0), 1),
                                                         y: min(max(drag.location.y / side, 0), 1)))
                        if activeStroke == nil {
                            activeStroke = .start(at: point,
                                                  colorHex: isEraser ? DrawingColor.eraserSentinel : colorHex,
                                                  isEraser: isEraser,
                                                  width: lineWidth)
                        } else {
                            activeStroke?.points.append(point)
                        }
                    }
            )
            .onChange(of: isDrawing) { _, drawing in
                guard !drawing else { return }
                if let stroke = activeStroke { strokes.append(stroke) }
                activeStroke = nil
            }
            .padding(.top, 4)
    }

    /// 写真を撮る・消すボタン。カメラのない端末では、写真を撮るボタンは出さない。
    @ViewBuilder
    private var photoButton: some View {
        if photo != nil {
            pillButton("camera.on.rectangle", "sticker_custom_remove_photo") { setPhoto(nil) }
        } else if CameraPicker.isAvailable {
            pillButton("camera.fill", "sticker_custom_take_photo") {
                if CameraPicker.isDenied {
                    showCameraDenied = true
                } else {
                    showCamera = true
                }
            }
        }
    }

    /// 背景を透明にするボタン（押すたびに切り替わる）。
    private var transparentButton: some View {
        pillButton("checkerboard.rectangle", "sticker_custom_transparent", isOn: isTransparent) {
            setTransparent(!isTransparent)
        }
        .disabled(isCuttingOut)
        .accessibilityAddTraits(isTransparent ? .isSelected : [])
    }

    private func pillButton(_ symbol: String, _ title: LocalizedStringKey, isOn: Bool = false,
                            action: @escaping () -> Void) -> some View {
        Button {
            SoundManager.shared.playTap()
            action()
        } label: {
            Label(title, systemImage: symbol)
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(isOn ? .white : DS.primary)
                .padding(.horizontal, 18)
                .padding(.vertical, 10)
                .background(Capsule().fill(isOn ? DS.primary : DS.primary.opacity(0.10)))
        }
        .buttonStyle(.plain)
    }

    private func iconButton(_ symbol: String, _ label: LocalizedStringKey, foreground: Color, background: Color,
                            action: @escaping () -> Void) -> some View {
        Button {
            SoundManager.shared.playTap()
            action()
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(foreground)
                .frame(width: 44, height: 44)
                .background(Circle().fill(background))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(label))
    }

    /// 線の太さ・消しゴム・ひとつ戻す。
    private var toolRow: some View {
        HStack(spacing: 10) {
            ForEach(Self.lineWidths, id: \.self) { width in
                Button {
                    SoundManager.shared.playTap()
                    lineWidth = width
                    isEraser  = false
                } label: {
                    Circle()
                        .fill(lineWidth == width && !isEraser ? DS.primary : DS.muted)
                        .frame(width: width * 240, height: width * 240)
                        .frame(width: 44, height: 44)
                        .background(Circle().fill(Color.black.opacity(0.05)))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(verbatim: "\(Int(width * 1000))"))
            }
            iconButton("eraser.fill", "drawing_eraser_label",
                       foreground: isEraser ? .white : DS.muted,
                       background: isEraser ? DS.primary : Color.black.opacity(0.05)) {
                isEraser.toggle()
            }
            iconButton("arrow.uturn.backward", "drawing_undo_label",
                       foreground: strokes.isEmpty ? DS.muted.opacity(0.4) : DS.muted,
                       background: Color.black.opacity(0.05)) {
                _ = strokes.popLast()
            }
            .disabled(strokes.isEmpty)
        }
    }

    /// クレヨンの色。シール帳と同じ12色。
    private var palette: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(DrawingColor.palette, id: \.hex) { color in
                    let isSelected = color.hex == colorHex && !isEraser
                    Button {
                        SoundManager.shared.playTap()
                        colorHex = color.hex
                        isEraser = false
                    } label: {
                        Circle()
                            .fill(Color(hex: color.hex))
                            .overlay(Circle().strokeBorder(Color.black.opacity(0.12), lineWidth: 1))
                            .frame(width: 34, height: 34)
                            .padding(3)
                            .overlay(Circle().strokeBorder(isSelected ? DS.primary : .clear, lineWidth: 3))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text(color.name.key))
                }
            }
            .padding(.horizontal, 2)
            .padding(.vertical, 2)
        }
        .frame(maxWidth: 520)
    }

    private var nameField: some View {
        TextField("sticker_custom_name_placeholder", text: $name)
            .font(.system(size: 16, weight: .medium, design: .rounded))
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(RoundedRectangle(cornerRadius: DS.inputRadius).fill(DS.card))
            .frame(maxWidth: 420)
            .onChange(of: name) { _, new in
                if new.count > CustomStickerTuning.maxNameLength {
                    name = String(new.prefix(CustomStickerTuning.maxNameLength))
                }
            }
    }

    private var makeButton: some View {
        VStack(spacing: 6) {
            Button {
                SoundManager.shared.playTap()
                showCreateConfirm = true
            } label: {
                Text("sticker_custom_make_button \(EnergyStore.format(price))")
                    .font(.system(size: 18, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                    .frame(maxWidth: 420)
                    .padding(.vertical, 14)
                    .background(RoundedRectangle(cornerRadius: DS.btnRadius)
                        .fill(hasContent && canAfford ? DS.energy : DS.muted.opacity(0.35)))
            }
            .buttonStyle(.plain)
            .disabled(!hasContent || !canAfford || isCuttingOut)

            if !canAfford {
                Text("sticker_custom_not_enough \(EnergyStore.formatShortage(price - energy.balance))")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(DS.muted)
                    .multilineTextAlignment(.center)
            }
        }
    }

    // MARK: 処理

    /// 写真を変える。背景を透明にしているなら、新しい写真も切り抜く。
    private func setPhoto(_ image: UIImage?) {
        photo  = image
        cutout = nil
        if isTransparent, image != nil {
            makeCutout()
        }
    }

    /// 背景の透明を切り替える。写真があれば、はじめて透明にするときに切り抜く。
    private func setTransparent(_ on: Bool) {
        isTransparent = on
        if on, photo != nil, cutout == nil {
            makeCutout()
        }
    }

    /// 写真を切り抜く。切り抜けなければ、透明をやめて知らせる。
    private func makeCutout() {
        guard let source = photo else { return }
        Task {
            let result = await StickerCutout.cutout(source)
            guard photo === source else { return }   // 切り抜いている間に写真が変わった
            if let result {
                cutout = result
            } else {
                isTransparent = false
                showCutoutFailed = true
            }
        }
    }

    /// 紙に出す写真。切り抜きの途中は、もとの写真のまま。
    private var displayedPhoto: UIImage? { isTransparent ? cutout ?? photo : photo }

    /// 保存する画像を作って、シールにする。
    private func create() {
        let side = CustomStickerTuning.imageSide
        let renderer = ImageRenderer(content: CustomStickerArt(photo: displayedPhoto, strokes: strokes, side: side,
                                                               isTransparent: isTransparent))
        renderer.scale    = 1
        renderer.isOpaque = false
        guard let png = renderer.uiImage?.pngData() else { return }

        if customStore.create(pngData: png, name: name) {
            SoundManager.shared.playCoinLand()
            SoundManager.shared.vibrate()
            dismiss()
        }
    }

    /// 写真を、長い辺が maxPhotoSide 以下になるよう描き直す。
    /// 小さい写真も描き直して、画像の向きを「上」にそろえる（切り抜きは画像の向きの情報を見ないため）。
    private static func shrunk(_ image: UIImage) -> UIImage {
        let longest = max(image.size.width, image.size.height)
        let ratio = min(maxPhotoSide / longest, 1)
        let size  = CGSize(width: image.size.width * ratio, height: image.size.height * ratio)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
    }
}
