//
//  SlidingPuzzleView.swift
//  FDL-TenBlitz
//
//  Created by 空飛ぶ研究室(FlyingDevLab) on 2026/11/03.
//

// スライドパズル（クロツキ・箱入り娘・華容道）の画面。3つのゲームで共有している。
// 違うのは SlidingPuzzleKind が持つ配置・名札・色だけ。
//
// ★ このファイルの構成 ★
//   SlidingPuzzleView … ルートView（ひとこと・手数・盤・ボタンを、そのゲームの色の台に載せる）
//   ─ 部品（private）─────────────────────────
//   PuzzleBoard       … 枠・盤・出口と、駒を並べる
//   PieceView         … 駒1つ（指でなぞって動かす）
//   PuzzleResultCard  … 解けたときに盤の上に重ねる表示
//
// ★ 盤の大きさ ★
//   画面の幅と高さの両方に収まる、いちばん大きいマスの大きさを計算して決める。
//   盤は 4:5（横:縦）。ボタンまで1画面に収め、遊んでいる途中でスクロールしなくて済むようにしている。
//
// ★ 台の色をゲームごとに変えている理由 ★
//   クロツキ（白と積み木）・箱入り娘（藍と欅）・華容道（栗色と紫檀）を並べたときに、
//   一目で別のオモチャだと分かるようにするため（Web 版の3本と同じ色）。

import SwiftUI

// MARK: - SlidingPuzzleView（ルート）

struct SlidingPuzzleView: View {

    @State private var viewModel: SlidingPuzzleViewModel

    init(kind: SlidingPuzzleKind) {
        // 箱入り娘は、前に選んでいたモードから始める。開いていなければ標準のまま
        let saved = UserDefaults.standard.string(forKey: UDKey.hakoiriLastMode)
            .flatMap(SlidingPuzzleKind.init(rawValue:))
        let start = saved.flatMap { kind.modes.contains($0) && PuzzleProgress.shared.isUnlocked($0.step) ? $0 : nil }
        _viewModel = State(initialValue: SlidingPuzzleViewModel(kind: start ?? kind))
    }

    private var kind:  SlidingPuzzleKind  { viewModel.kind }
    private var theme: SlidingPuzzleTheme { kind.theme }

    /// 枠の太さ（pt）。出口の高さもこの値
    private let rimWidth: CGFloat = 14

    /// 盤以外（ひとこと・手数・地名・出口の名前・ボタン・余白）が使う高さの見積もり（pt）。
    /// 盤のマスの大きさを決めるのに使う。ここを直し忘れると、背の低い画面でボタンがはみ出す。
    private let chromeHeight: CGFloat = 250
    /// モードの切り替えがあるゲームで、そのぶん足す高さ（pt）
    private let modeBarHeight: CGFloat = 46

    var body: some View {
        GeometryReader { geo in
            let cell = cellSize(for: geo.size)
            VStack(spacing: 10) {
                Text(kind.tagline)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(theme.muted)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)

                if kind.modes.count > 1 { modeBar }

                stats

                PuzzleBoard(viewModel: viewModel, cell: cell, rimWidth: rimWidth)

                controls
                    .frame(width: cell * 4 + rimWidth * 2)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(RoundedRectangle(cornerRadius: DS.cardRadius).fill(theme.ground))
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .onAppear {
            EnergyStore.shared.beginSession()   // 結果画面に出す「今回の獲得量」を 0 に戻す
            playScreenshotScene()
        }
    }

    /// 幅にも高さにも収まる、いちばん大きいマスの大きさ（pt）
    private func cellSize(for size: CGSize) -> CGFloat {
        let byWidth  = (size.width - 24 - 28 - rimWidth * 2) / CGFloat(SlidingPuzzleViewModel.cols)
        let chrome = chromeHeight + (kind.modes.count > 1 ? modeBarHeight : 0)
        let byHeight = (size.height - chrome - rimWidth * 2) / CGFloat(SlidingPuzzleViewModel.rows)
        return max(40, min(byWidth, byHeight, 96))
    }

    // MARK: モードの切り替え

    /// 箱入り娘の「標準」「むずかしい」。切り替えると盤は最初からになる（途中の盤は保存しない）。
    /// まだ開いていないモードは 🔒 を付けて薄く見せ、この先に何があるかだけ分かるようにする。
    private var modeBar: some View {
        HStack(spacing: 8) {
            ForEach(kind.modes) { mode in
                let isOn = mode == kind
                let isOpen = PuzzleProgress.shared.isUnlocked(mode.step)
                Button {
                    guard !isOn else { return }
                    SoundManager.shared.playTap()
                    UserDefaults.standard.set(mode.rawValue, forKey: UDKey.hakoiriLastMode)
                    withAnimation(.easeInOut(duration: 0.2)) {
                        viewModel = SlidingPuzzleViewModel(kind: mode)
                    }
                    EnergyStore.shared.beginSession()   // 結果画面に出す「今回の獲得量」を 0 に戻す
                } label: {
                    HStack(spacing: 4) {
                        if !isOpen { Text(verbatim: "🔒").font(.system(size: 12)) }
                        Text(mode.modeLabel)
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                    .foregroundStyle(isOn ? theme.accentInk : theme.text)
                    .frame(maxWidth: .infinity)
                    .frame(height: 36)
                    .background(RoundedRectangle(cornerRadius: 10).fill(isOn ? theme.accent : theme.groundDeep))
                }
                .buttonStyle(.plain)
                .disabled(!isOpen)
                .opacity(isOpen ? 1 : 0.55)
                .accessibilityValue(isOpen ? Text(verbatim: "") : Text("puzzle_locked"))
                .accessibilityAddTraits(isOn ? .isSelected : [])
            }
        }
    }

    // MARK: 手数とクリア回数

    /// 手数・クリアした回数（🏆）・最短の手数。時間は出さない（SlidingPuzzleViewModel 冒頭を参照）。
    private var stats: some View {
        HStack(spacing: 10) {
            statBox {
                Text("slide_moves")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(theme.muted)
                Text(verbatim: "\(viewModel.moves)")
                    .font(.system(size: 22, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(theme.text)
                    .contentTransition(.numericText())
                    .animation(.easeOut(duration: 0.15), value: viewModel.moves)
            }
            .accessibilityElement(children: .combine)

            // クリアした回数の印。1回目は 🏆、2回目からは 🏆 2。まだのうちは出さない。
            // 見せるだけの数字で、何かを開く条件には使っていない。
            if viewModel.clears > 0 {
                statBox {
                    Text(verbatim: viewModel.clears == 1 ? "🏆" : "🏆 \(viewModel.clears)")
                        .font(.system(size: 20, weight: .heavy, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(theme.text)
                }
                .accessibilityLabel(Text("slide_clears \(viewModel.clears)"))
            }

            statBox {
                Text("slide_par \(kind.par)")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(theme.muted)
                if let best = viewModel.best {
                    Text("slide_best \(best)")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(theme.accent)
                }
            }
            .accessibilityElement(children: .combine)
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private func statBox<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(spacing: 0) { content() }
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .frame(minWidth: 86)
            .frame(maxHeight: .infinity)
            .background(RoundedRectangle(cornerRadius: 12).fill(theme.groundDeep))
    }

    // MARK: ボタン

    /// 盤の下にまとめている。盤の上や横に置くと、駒を動かしている指がそのままボタンに届いてしまう。
    private var controls: some View {
        HStack(spacing: 10) {
            PuzzleButton(label: "slide_undo", icon: "arrow.uturn.backward", theme: theme,
                         isPrimary: false, disabled: !viewModel.canUndo) { viewModel.undo() }
            PuzzleButton(label: "slide_reset", icon: "arrow.counterclockwise", theme: theme,
                         isPrimary: false, disabled: false) {
                withAnimation(.easeOut(duration: 0.2)) { viewModel.reset() }
            }
        }
    }

    // MARK: 撮影モード

    /// 撮影モード（ScreenshotMode.swift を参照）: 盤を開いたまま、何もしない。
    private func playScreenshotScene() {
        guard ScreenshotMode.isActive else { return }
        viewModel.reset()
    }
}

// MARK: - 盤

/// 枠・盤・出口と、駒。駒の位置はマス単位で持ち、cell（1マスの大きさ）を掛けて置く。
private struct PuzzleBoard: View {
    var viewModel: SlidingPuzzleViewModel
    let cell:      CGFloat
    let rimWidth:  CGFloat

    private var kind:  SlidingPuzzleKind  { viewModel.kind }
    private var theme: SlidingPuzzleTheme { kind.theme }

    private var gridWidth:  CGFloat { cell * CGFloat(SlidingPuzzleViewModel.cols) }
    private var gridHeight: CGFloat { cell * CGFloat(SlidingPuzzleViewModel.rows) }

    var body: some View {
        VStack(spacing: 4) {
            // 盤の上の地名（華容道だけ「赤壁」）。他のゲームも同じ高さを空けておき、盤の位置を揃える
            placeLabel(kind.placeNames?.top, color: theme.muted)

            ZStack(alignment: .bottom) {
                frame
                // 出口。下の枠を2マスぶん切り欠いて、盤の底の色で塗る
                Rectangle()
                    .fill(theme.recess)
                    .frame(width: gridWidth / 2, height: rimWidth)
            }
            .overlay {
                if viewModel.showsResult {
                    PuzzleResultCard(viewModel: viewModel)
                        .transition(.opacity.combined(with: .offset(y: 8)))
                }
            }

            // 出口の名前（華容道は「江陵」。それ以外は「でぐち」を訳して出す）
            if let bottom = kind.placeNames?.bottom {
                placeLabel(bottom, color: theme.accent)
            } else {
                Text("slide_exit")
                    .font(.system(size: 15, weight: .heavy, design: .rounded))
                    .tracking(4)
                    .foregroundStyle(theme.accent)
                    .frame(height: 22)
            }
        }
    }

    /// 盤の上下に出す地名。字間を広く取り、看板らしく見せる（駒の文字と同じ大きさだと盤の一部に見えるため）
    @ViewBuilder
    private func placeLabel(_ text: String?, color: Color) -> some View {
        Text(verbatim: text ?? " ")
            .font(.system(size: 17, weight: .bold, design: .serif))
            .tracking(14)
            .foregroundStyle(color)
            .typesettingLanguage(theme.typesetting ?? .init(identifier: "en"))
            .frame(height: 22)
            .accessibilityHidden(true)
    }

    // 枠（光が当たる上辺から影の下辺へのグラデーション）と、盤の底と、駒
    private var frame: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 5)
                .fill(theme.recess)
                .shadow(color: .black.opacity(0.35), radius: 4, y: 2)

            ForEach(viewModel.pieces) { piece in
                PieceView(viewModel: viewModel, piece: piece, cell: cell)
            }
        }
        .frame(width: gridWidth, height: gridHeight)
        .padding(rimWidth)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(LinearGradient(colors: [theme.rimHi, theme.rim], startPoint: .topLeading, endPoint: .bottomTrailing))
                .shadow(color: .black.opacity(0.35), radius: 10, y: 8)
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("slide_board"))
    }
}

// MARK: - 駒

/// 駒1つ。指でなぞると、動ける範囲の中だけ指に付いてくる。離すと一番近いマスに吸着する。
private struct PieceView: View {
    var viewModel: SlidingPuzzleViewModel
    let piece:     SlidingPiece
    let cell:      CGFloat

    private var theme: SlidingPuzzleTheme { viewModel.kind.theme }
    private var isGoal: Bool { piece.id == viewModel.kind.goalID }
    private var isDragging: Bool { viewModel.draggingID == piece.id }

    /// 表示する位置（マス単位）。ドラッグ中は指に付いてくる半端な位置、
    /// 解けたあとの出口へ運ぶ駒は盤の下（出口から抜けていく）。
    private var position: (x: Double, y: Double) {
        if isGoal && viewModel.isEscaping {
            return (Double(piece.x), Double(SlidingPuzzleViewModel.rows) + 0.4)
        }
        return viewModel.dragPosition(of: piece) ?? (Double(piece.x), Double(piece.y))
    }

    var body: some View {
        face
            .padding(cell * 0.04)   // 駒と駒の隙間
            .frame(width: cell * CGFloat(piece.w), height: cell * CGFloat(piece.h))
            .contentShape(Rectangle())
            .offset(x: cell * position.x, y: cell * position.y)
            .opacity(isGoal && viewModel.isEscaping ? 0 : 1)
            // ドラッグ中は指に追従させたいのでアニメーションを止める。離したときの吸着は dragEnded 側で付ける
            .transaction { if isDragging { $0.animation = nil } }
            .zIndex(isDragging ? 3 : 1)
            // ★ 移動量を画面全体の座標で測っている理由 ★
            //   駒は指に付いて動くので、駒自身の座標で測ると、測る物差しごと動いてしまい、
            //   移動量が小さく出たり震えたりする。画面全体の座標なら物差しが動かない。
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .global)
                    .onChanged { value in
                        viewModel.dragChanged(piece,
                                              dx: value.translation.width / cell,
                                              dy: value.translation.height / cell)
                    }
                    .onEnded { _ in
                        withAnimation(.easeOut(duration: 0.16)) { viewModel.dragEnded(piece) }
                    }
            )
            .allowsHitTesting(!viewModel.isWon)
            // VoiceOver では、指でなぞる代わりに「上へ・下へ・左へ・右へ」で1マスずつ動かす（Web 版の矢印キーと同じ）
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(verbatim: piece.label))
            .accessibilityAction(named: Text("slide_move_up"))    { viewModel.step(piece, dx: 0, dy: -1) }
            .accessibilityAction(named: Text("slide_move_down"))  { viewModel.step(piece, dx: 0, dy: 1) }
            .accessibilityAction(named: Text("slide_move_left"))  { viewModel.step(piece, dx: -1, dy: 0) }
            .accessibilityAction(named: Text("slide_move_right")) { viewModel.step(piece, dx: 1, dy: 0) }
    }

    // 漆や木の面。艶のかぶせと、下の木口の厚みで立体にしている
    private var face: some View {
        let radius = cell * 0.1
        return ZStack {
            RoundedRectangle(cornerRadius: radius)
                .fill(piece.fill)
                .overlay(
                    RoundedRectangle(cornerRadius: radius)
                        .fill(LinearGradient(colors: [.white.opacity(0.22), .clear],
                                             startPoint: .topLeading, endPoint: .center))
                )
                .overlay(
                    // 下の木口の厚み
                    RoundedRectangle(cornerRadius: radius)
                        .strokeBorder(Color.black.opacity(0.18), lineWidth: 1)
                )
                .overlay {
                    // 出口へ運ぶ駒だけ、内側に金の縁を回して別格にする（文字のあるゲームだけ）
                    if isGoal && piece.face != nil {
                        RoundedRectangle(cornerRadius: radius * 0.8)
                            .inset(by: cell * 0.06)
                            .stroke(theme.accent.opacity(0.4), lineWidth: cell * 0.04)
                    }
                }
                .shadow(color: .black.opacity(isDragging ? 0.5 : 0.35),
                        radius: isDragging ? 6 : 0, y: isDragging ? 6 : 3)

            if let text = piece.face {
                label(text)
            }
        }
        .scaleEffect(isDragging ? 1.02 : 1)
        .animation(.easeOut(duration: 0.12), value: isDragging)
    }

    /// 駒の文字。読み（ふりがな・注音）を上に小さく添える。
    /// 縦に2マスの駒は、駒の形に沿って縦書きにする（1文字ずつ縦に積む）。
    private func label(_ text: String) -> some View {
        let size = cell * (isGoal ? 0.46 : 0.3)
        let vertical = piece.h > piece.w
        let body = vertical ? text.map(String.init).joined(separator: "\n") : text
        return VStack(spacing: cell * 0.02) {
            if let ruby = piece.ruby {
                Text(verbatim: ruby)
                    .font(.system(size: max(7, size * (isGoal ? 0.26 : 0.36)), weight: .regular))
                    .opacity(0.75)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
            }
            Text(verbatim: body)
                .font(.system(size: size, weight: .bold, design: .serif))
                .tracking(piece.w > piece.h ? size * 0.22 : 0)
                .lineSpacing(0)
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.5)
        }
        .foregroundStyle(piece.ink)
        .typesettingLanguage(theme.typesetting ?? .init(identifier: "en"))
        .padding(cell * 0.04)
    }
}

// MARK: - ボタン

private struct PuzzleButton: View {
    let label:     LocalizedStringKey
    let icon:      String
    let theme:     SlidingPuzzleTheme
    let isPrimary: Bool
    let disabled:  Bool
    let action:    () -> Void

    var body: some View {
        Button {
            SoundManager.shared.vibrate()
            action()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .bold))
                Text(label)
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .foregroundStyle(isPrimary ? theme.accentInk : theme.text)
            .frame(maxWidth: .infinity)
            .frame(height: 48)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isPrimary ? theme.accent : theme.groundDeep)
                    .shadow(color: .black.opacity(0.3), radius: 0, y: 3)
            )
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.4 : 1)
    }
}

// MARK: - 解けたとき

/// 盤の上に重ねる。別の画面に切り替えないのは、解けた盤面を見せたまま結果を出したいため。
private struct PuzzleResultCard: View {
    var viewModel: SlidingPuzzleViewModel

    private var kind:  SlidingPuzzleKind  { viewModel.kind }
    private var theme: SlidingPuzzleTheme { kind.theme }

    var body: some View {
        let moves = viewModel.moves
        VStack(spacing: 8) {
            Text("slide_escaped")
                .font(.system(size: 28, weight: .heavy, design: .rounded))
                .foregroundStyle(theme.accent)

            Text("slide_result \(moves)")
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(theme.text)

            Group {
                if let previous = viewModel.previousBest {
                    if viewModel.isNewBest {
                        Text("slide_best_new \(previous)")
                    } else {
                        Text("slide_best \(previous)")
                    }
                } else {
                    Text("slide_best \(moves)")
                }
            }
            .font(.system(size: 14, weight: .bold, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(theme.accent)

            Group {
                if moves == kind.par {
                    Text("slide_note_shortest")
                } else {
                    Text("slide_note_par \(kind.par)")
                }
            }
            .font(.system(size: 13, weight: .medium, design: .rounded))
            .foregroundStyle(theme.muted)
            .multilineTextAlignment(.center)

            // 今回のクリアで開いたもの
            if let opened = viewModel.openedStep {
                Text("puzzle_opened \(opened.openedName)")
                    .font(.system(size: 15, weight: .black, design: .rounded))
                    .foregroundStyle(theme.accent)
                    .multilineTextAlignment(.center)
            }

            EnergyRewardBanner()
                .padding(.vertical, 2)

            PuzzleButton(label: "slide_again", icon: "arrow.counterclockwise", theme: theme,
                         isPrimary: true, disabled: false) {
                withAnimation(.easeOut(duration: 0.2)) { viewModel.reset() }
            }
            .frame(maxWidth: 220)
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(RoundedRectangle(cornerRadius: 14).fill(theme.groundDeep.opacity(0.95)))
    }
}
