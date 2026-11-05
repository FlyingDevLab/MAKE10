//
//  ChessView.swift
//  FDL-TenBlitz
//
//  チェスの画面。レッスンと、「あそぶ」（コンピュータと・ふたりで・ならべて）を切り替える。
//
// ★ このファイルの構成 ★
//   ChessView       … ルート。モード・ひとこと・盤・棋譜・ボタンを縦に積む
//   ChessResultFooter … 決着のときに盤の下へ出す部分
//
// ★ 決着を盤に重ねない ★
//   チェックメイトの形は、どう負けたか（どう勝ったか）そのものなので、隠さずに見せる。
//   勝ち負けは盤の上のひとことの場所に、理由と報酬とボタンは盤の下に出す（Web 版と同じ）。
//
// ★ 強さのことは何も出さない ★
//   段が目的にならないように、いま何段かも、変わったことも、どこにも書かない。
//

import SwiftUI

// MARK: - 切り替え

enum ChessSection: String, CaseIterable, Identifiable {
    case lessons, computer, twoPlayers, sandbox
    var id: String { rawValue }

    var mode: ChessViewModel.Mode? { ChessViewModel.Mode(rawValue: rawValue) }

    var label: LocalizedStringKey {
        mode?.label ?? "chess_section_lessons"
    }
}

// MARK: - ChessView（ルート）

struct ChessView: View {

    @State private var section = ChessStore.lastSection
    @State private var viewModel = ChessViewModel(mode: ChessStore.lastSection.mode ?? .computer)

    var body: some View {
        GeometryReader { geo in
            let side = boardSide(for: geo.size)
            VStack(spacing: 8) {
                sectionBar
                if section == .lessons {
                    ChessLessonsRoot()
                } else {
                    message
                    ChessBoardView(pieces: viewModel.boardPieces, marks: viewModel.boardMarks,
                                   isFlipped: viewModel.isFlipped, side: side,
                                   promotionChoices: viewModel.promotionChoices,
                                   onPromote: viewModel.choosePromotion) { viewModel.tap(square: $0) }
                    if viewModel.phase == .playing || viewModel.phase == .finished {
                        ChessRecordLine(text: viewModel.recordText, count: viewModel.sans.count, width: side)
                    }
                    controls.frame(width: side)
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 18)      // ヘッダーのエネルギーの表示が台に少しかかるぶん
            .padding(.bottom, 10)
            // 上に揃える。真ん中に揃えると、下のボタンが変わるたびに盤が上下に動く
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            // 壁紙の上でも文字が読めるように、台に載せる
            .background(RoundedRectangle(cornerRadius: DS.cardRadius).fill(DS.card))
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
        }
        .onAppear {
            if section != .lessons { viewModel.appear() }
        }
        .onDisappear { viewModel.disappear() }
    }

    /// 盤以外が使う高さの見積もり（pt）。背の低い画面でボタンがはみ出さないようにする。
    private var chromeHeight: CGFloat {
        switch viewModel.phase {
        case .arranging:     return 338
        case .choosingColor: return 208
        case .playing:       return 238
        case .finished:      return viewModel.mode == .computer && viewModel.didPlayerWin ? 353 : 278
        }
    }

    private func boardSide(for size: CGSize) -> CGFloat {
        max(220, min(size.width - 44, size.height - chromeHeight, 640))
    }

    // MARK: 切り替え

    private func select(_ new: ChessSection) {
        SoundManager.shared.playTap()
        // 今の対局は 1 手ごとに保存してあるので、切り替えても失われない
        viewModel.disappear()
        section = new
        ChessStore.lastSection = new
        if let mode = new.mode {
            viewModel = ChessViewModel(mode: mode)
            viewModel.appear()
        }
    }

    private var sectionBar: some View {
        HStack(spacing: 5) {
            ForEach(ChessSection.allCases) { item in
                ChessChip(text: Text(item.label), isOn: item == section) {
                    if item != section { select(item) }
                }
            }
        }
    }

    // MARK: ひとこと

    private var messageKey: LocalizedStringKey {
        switch viewModel.phase {
        case .choosingColor:
            return "chess_choose_color"
        case .arranging:
            return viewModel.arrangeNotice ?? "chess_arrange_hint"
        case .finished:
            return resultTitle
        case .playing:
            if viewModel.isThinking { return "chess_thinking" }
            let position = viewModel.game.position
            if position.inCheck(position.turn) { return "chess_check" }
            if viewModel.vsComputer { return "chess_your_turn" }
            return position.turn == .white ? "chess_turn_white" : "chess_turn_black"
        }
    }

    /// 決着のひとこと。勝ち負けを、盤の上のいつもの場所に大きく出す。
    private var resultTitle: LocalizedStringKey {
        guard let ending = viewModel.ending else { return "chess_draw" }
        switch ending {
        case .checkmate(let winner):
            if viewModel.vsComputer { return viewModel.didPlayerWin ? "chess_win" : "chess_lose" }
            return winner == .white ? "chess_white_wins" : "chess_black_wins"
        case .resigned:
            return "chess_lose"
        case .stalemate, .material, .repetition, .fifty:
            return "chess_draw"
        }
    }

    private var messageColor: Color {
        if viewModel.didPlayerWin { return DS.primary }
        return viewModel.arrangeNotice != nil && viewModel.phase == .arranging ? ChessInk.warn : DS.textBody
    }

    private var message: some View {
        Text(messageKey)
        .font(.system(size: viewModel.phase == .finished ? 21 : 15, weight: viewModel.phase == .finished ? .heavy : .bold, design: .rounded))
        .foregroundStyle(messageColor)
        .lineLimit(1)
        .minimumScaleFactor(0.7)
        .frame(height: 26)
        .accessibilityAddTraits(.updatesFrequently)
    }

    // MARK: ボタン

    @ViewBuilder
    private var controls: some View {
        switch viewModel.phase {
        case .choosingColor:
            HStack(spacing: 8) {
                ChessButton(label: "chess_play_white", isPrimary: ChessStore.lastColor == .white) {
                    viewModel.choose(color: .white)
                }
                ChessButton(label: "chess_play_black", isPrimary: ChessStore.lastColor == .black) {
                    viewModel.choose(color: .black)
                }
            }
        case .arranging:
            arrangeControls
        case .playing:
            HStack(spacing: 8) {
                ChessButton(label: "chess_undo", disabled: !viewModel.canUndo) { viewModel.undo() }
                playingSecondButton
            }
        case .finished:
            ChessResultFooter(viewModel: viewModel)
        }
    }

    @ViewBuilder
    private var playingSecondButton: some View {
        if viewModel.mode == .computer {
            ChessButton(label: viewModel.isConfirming ? "chess_confirm_resign" : "chess_resign",
                        isWarning: viewModel.isConfirming) { viewModel.resign() }
        } else if viewModel.mode == .twoPlayers {
            ChessButton(label: viewModel.isConfirming ? "chess_confirm_restart" : "chess_restart",
                        isWarning: viewModel.isConfirming) { viewModel.restartTwoPlayers() }
        } else {
            ChessButton(label: viewModel.isConfirming ? "chess_confirm_restart" : "chess_arrange_again",
                        isWarning: viewModel.isConfirming) { viewModel.backToArranging() }
        }
    }

    private var arrangeControls: some View {
        VStack(spacing: 6) {
            let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 6)
            LazyVGrid(columns: columns, spacing: 4) {
                ForEach(ChessViewModel.palette, id: \.self) { piece in
                    ChessPaletteTile(piece: piece, isHeld: viewModel.held == piece) { viewModel.hold(piece) }
                }
            }
            HStack(spacing: 6) {
                ChessButton(label: "chess_start_position", height: 36) { viewModel.fillStartPosition() }
                ChessButton(label: "chess_clear_board", height: 36) { viewModel.clearArrangement() }
            }
            HStack(spacing: 6) {
                ChessButton(label: "chess_sandbox_two", isPrimary: true, height: 44) {
                    viewModel.startArranged(computerColor: nil)
                }
                ChessButton(label: "chess_sandbox_white", isPrimary: true, height: 44) {
                    viewModel.startArranged(computerColor: .white)
                }
                ChessButton(label: "chess_sandbox_black", isPrimary: true, height: 44) {
                    viewModel.startArranged(computerColor: .black)
                }
            }
        }
    }
}

// MARK: - 決着

/// 決着のときに盤の下へ出す部分。勝ち負けは盤の上のひとことの場所に出している。
private struct ChessResultFooter: View {
    var viewModel: ChessViewModel

    private var reason: LocalizedStringKey {
        switch viewModel.ending {
        case .checkmate, nil: return "chess_checkmate"
        case .resigned:       return "chess_resigned"
        case .stalemate:      return "chess_reason_stalemate"
        case .material:       return "chess_reason_material"
        case .repetition:     return "chess_reason_repetition"
        case .fifty:          return "chess_reason_fifty"
        }
    }

    var body: some View {
        VStack(spacing: 8) {
            Text(reason)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(DS.textBody)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.8)

            if viewModel.mode == .computer && viewModel.didPlayerWin {
                EnergyRewardBanner()
            }

            HStack(spacing: 8) {
                // ふたりで指したときだけ、決着のあとも「もどす」が使える
                if !viewModel.vsComputer {
                    ChessButton(label: "chess_undo", disabled: !viewModel.canUndo) { viewModel.undo() }
                }
                ChessButton(label: "chess_again", isPrimary: true) { viewModel.playAgain() }
            }
        }
    }
}
