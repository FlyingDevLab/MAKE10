//
//  ChessLessonViews.swift
//  FDL-TenBlitz
//
//  レッスンの画面。もくじと、レッスン 1 回ぶんの画面。
//
// ★ 盤は「あそぶ」と同じ大きさ ★
//   小さい盤はマスが押しにくく、駒の形も読みにくい。
//   iPhone では同じ大きさの盤と説明が 1 画面に並ばないので、
//   開いたらまず説明を読み、「やってみる」で盤へ進む。説明には上のボタンで戻れる。
//   縦に余裕のある画面では、説明と盤を並べて出す（説明は盤の形を指して話すため）。
//
// ★ レッスンを変えるときは session を作り直す ★
//   同じ session の中身を差し替えると、配列の長さが変わったときに SwiftUI が
//   古い番号のまま ForEach の中身を読み直して落ちる（組み合わせのボタンがある回で実際に落ちた）。
//   作り直せば画面も丸ごと作り直され、説明のスクロールや「読んでいるところ」も自然に戻る。
//

import SwiftUI

// MARK: - 入口

struct ChessLessonsRoot: View {
    private static let book = ChessLessonBook.load()

    @State private var volumeIndex = 0
    @State private var session: ChessLessonSession?

    private var volumes: [ChessLessonVolume] { Self.book?.volumes ?? [] }

    var body: some View {
        if let session {
            ChessLessonScreen(session: session, onOpen: show, onClose: { self.session = nil },
                              onNextVolume: openNextVolume)
                .id(ObjectIdentifier(session))
        } else if volumes.indices.contains(volumeIndex) {
            contents(volumes[volumeIndex])
        }
    }

    /// いまの巻のレッスンを開く。
    private func show(_ index: Int) {
        let new = ChessLessonSession(volume: volumes[volumeIndex], index: index,
                                     hasNextVolume: volumeIndex + 1 < volumes.count)
        new.sound = Self.play
        session = new
    }

    private func openNextVolume() {
        guard volumeIndex + 1 < volumes.count else { return }
        SoundManager.shared.playTap()
        volumeIndex += 1
        show(0)
    }

    private static func play(_ sound: ChessLessonSession.Sound) {
        switch sound {
        case .tap:     SoundManager.shared.playTap()
        case .capture:
            SoundManager.shared.playTap()
            SoundManager.shared.vibrate()
        case .wrong:   SoundManager.shared.playWrong()
        case .done:    SoundManager.shared.playCorrect()
        }
    }

    // MARK: もくじ

    private func contents(_ volume: ChessLessonVolume) -> some View {
        VStack(spacing: 8) {
            HStack(spacing: 5) {
                ForEach(volumes.indices, id: \.self) { index in
                    ChessChip(text: Text(verbatim: "\(volumes[index].no). \(volumes[index].title)"),
                              isOn: index == volumeIndex, onFill: ChessMarkInk.askDeep,
                              fontSize: 14, height: 36) {
                        SoundManager.shared.playTap()
                        volumeIndex = index
                    }
                }
            }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 6) {
                    ForEach(volume.chapters.indices, id: \.self) { chapter in
                        Text(verbatim: volume.chapters[chapter].text)
                            .font(.system(size: 14, weight: .heavy, design: .rounded))
                            .foregroundStyle(DS.muted)
                            .padding(.top, chapter == 0 ? 2 : 10)
                        ForEach(volume.lessons.indices.filter { volume.lessons[$0].chapter == chapter }, id: \.self) { index in
                            Button {
                                SoundManager.shared.playTap()
                                show(index)
                            } label: {
                                HStack(spacing: 10) {
                                    Text(verbatim: String(index + 1))
                                        .font(.system(size: 14, weight: .bold, design: .rounded))
                                        .monospacedDigit()
                                        .foregroundStyle(DS.muted)
                                        .frame(width: 24)
                                    Text(verbatim: volume.lessons[index].title)
                                        .font(.system(size: 15, weight: .bold, design: .rounded))
                                        .foregroundStyle(DS.textPrimary)
                                        .multilineTextAlignment(.leading)
                                    Spacer(minLength: 0)
                                }
                                .padding(.horizontal, 10)
                                .frame(minHeight: 42)
                                .background(RoundedRectangle(cornerRadius: DS.rowRadius).fill(DS.choiceFill))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }
}

// MARK: - レッスン 1 回

private struct ChessLessonScreen: View {
    let session: ChessLessonSession
    let onOpen: (Int) -> Void
    let onClose: () -> Void
    let onNextVolume: () -> Void

    /// 説明を読んでいるところか。開いたらまず説明を読む
    @State private var isReading = true

    /// 課題の文の高さ（実測）。長い文でもボタンが画面の外へ出ないように、盤の大きさの計算に入れる
    @State private var taskHeight: CGFloat = 40

    /// 盤と課題のほかに要る高さ（pt）。上の行・ひとこと・棋譜・ボタンと、そのあいだ
    private var fixedHeight: CGFloat {
        var height: CGFloat = 156 + taskHeight
        if !session.sets.isEmpty { height += 40 }
        if session.isSetup { height += 50 }
        return height
    }

    /// 「あそぶ」と同じ大きさ。幅いっぱいで、上限も同じ
    private func boardSide(for size: CGSize) -> CGFloat {
        max(220, min(size.width, size.height - fixedHeight, 640))
    }

    /// 盤と並べても説明が読めるだけの高さが余っているか
    private func hasRoomForText(_ size: CGSize) -> Bool {
        size.height - fixedHeight - boardSide(for: size) >= 170
    }

    var body: some View {
        GeometryReader { geo in
            let side = boardSide(for: geo.size)
            let beside = hasRoomForText(geo.size)
            VStack(spacing: 6) {
                navigation(canSwitch: !beside)
                if beside {
                    ScrollView { explanation }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    boardArea(side: side)
                } else if isReading {
                    ScrollView { explanation }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    ChessButton(label: "chess_try_it", isPrimary: true) {
                        SoundManager.shared.playTap()
                        isReading = false
                    }
                } else {
                    boardArea(side: side)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
    }

    @ViewBuilder
    private func boardArea(side: CGFloat) -> some View {
        taskLine
        if !session.sets.isEmpty { setsBar }
        ChessBoardView(pieces: session.pieces, marks: session.marks, side: side,
                       promotionChoices: session.promotionChoices,
                       onPromote: session.choosePromotion) { session.tap(square: $0) }
        messageLine
        if session.isSetup { palette(width: side) }
        // 空でも場所を取る。手を指した瞬間に盤が動くと、押そうとした指が外れる
        ChessRecordLine(text: session.recordText, count: session.record.count, width: side,
                        fontSize: 12, height: 18)
        controls.frame(width: side)
    }

    // MARK: 上の行

    private func navigation(canSwitch: Bool) -> some View {
        HStack(spacing: 6) {
            Button(action: onClose) {
                Label { Text("chess_lesson_list") } icon: { Image(systemName: "list.bullet") }
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(DS.textPrimary)
                    .frame(height: 32)
                    .padding(.horizontal, 8)
                    .background(RoundedRectangle(cornerRadius: DS.rowRadius).fill(DS.choiceFill))
            }
            .buttonStyle(.plain)

            Spacer(minLength: 0)
            Text(verbatim: "\(session.index + 1) / \(session.volume.lessons.count)")
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(DS.muted)
            Spacer(minLength: 0)

            if canSwitch && !isReading {
                iconButton("text.book.closed", label: "chess_lesson_text") {
                    isReading = true
                }
            }
            iconButton("chevron.left", label: "chess_prev_lesson", disabled: !session.hasPrevious) {
                onOpen(session.index - 1)
            }
            iconButton("chevron.right", label: "chess_next_lesson", disabled: !session.hasNext) {
                onOpen(session.index + 1)
            }
        }
    }

    private func iconButton(_ name: String, label: LocalizedStringKey, disabled: Bool = false,
                            action: @escaping () -> Void) -> some View {
        Button {
            SoundManager.shared.playTap()
            action()
        } label: {
            Image(systemName: name)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(DS.textPrimary)
                .frame(width: 36, height: 32)
                .background(RoundedRectangle(cornerRadius: DS.rowRadius).fill(DS.choiceFill))
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.35 : 1)
        .accessibilityLabel(Text(label))
    }

    // MARK: 説明

    private var explanation: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(verbatim: session.lesson.title)
                .font(.system(size: 19, weight: .heavy, design: .rounded))
                .foregroundStyle(DS.textPrimary)
            ForEach(Array(session.lesson.body.enumerated()), id: \.offset) { _, item in
                block(item)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func block(_ block: ChessLesson.Block) -> some View {
        switch block.t {
        case "pairs":
            VStack(spacing: 4) {
                ForEach(Array((block.items ?? []).enumerated()), id: \.offset) { _, item in
                    pairRow(item)
                }
            }
        case "key":
            Text(verbatim: block.text)
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(ChessMarkInk.askDeep)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(RoundedRectangle(cornerRadius: DS.rowRadius).fill(ChessMarkInk.ask.opacity(0.12)))
        default:
            Text(verbatim: block.text)
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .foregroundStyle(DS.textBody)
                .lineSpacing(3)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// 用語の組。駒の形・英語・日本語・棋譜の記号を 1 行に並べる。
    /// 棋譜の N が Knight の N であることは、並べないと伝わらない。
    private func pairRow(_ item: ChessLesson.PairItem) -> some View {
        HStack(spacing: 8) {
            if let letter = item.pc?.uppercased().first {
                HStack(spacing: 0) {
                    if let white = ChessPiece(fen: letter) { ChessPieceView(piece: white) }
                    if let black = ChessPiece(fen: Character(String(letter).lowercased())) { ChessPieceView(piece: black) }
                }
                .frame(width: 52, height: 26)
            }
            Text(verbatim: item.en)
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(DS.textPrimary)
            if ChessText.isJapanese {
                Text(verbatim: item.ja)
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(DS.textBody)
            }
            Spacer(minLength: 0)
            if let sym = ChessText.isJapanese ? item.symJa ?? item.sym : item.sym, !sym.isEmpty {
                Text(verbatim: sym)
                    .font(.system(size: 14, weight: .heavy, design: .rounded))
                    .foregroundStyle(ChessInk.frame)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(RoundedRectangle(cornerRadius: DS.smallRadius).fill(DS.choiceFill))
    }

    // MARK: 課題

    /// 課題の文。「できた！」に変わっても高さを保つので、盤が動かない。
    private var taskLine: some View {
        ZStack {
            Text(verbatim: session.lesson.task.text)
                .foregroundStyle(DS.textPrimary)
                .opacity(session.isDone ? 0 : 1)
            if session.isDone {
                Group {
                    if session.isLastTask {
                        Text("chess_volume_done \(session.volume.no)")
                    } else {
                        Text("chess_done")
                    }
                }
                .foregroundStyle(ChessMarkInk.ok)
            }
        }
        .font(.system(size: 14, weight: .heavy, design: .rounded))
        .multilineTextAlignment(.center)
        // 課題は途中で切らない。やることが読めないと始まらない
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, minHeight: 20)
        .onGeometryChange(for: CGFloat.self, of: \.size.height) { taskHeight = $0 }
    }

    private var messageLine: some View {
        Text(verbatim: session.message.isEmpty ? " " : session.message)
            .font(.system(size: 13, weight: .bold, design: .rounded))
            .foregroundStyle(messageColor)
            .multilineTextAlignment(.center)
            .lineLimit(2)
            .minimumScaleFactor(0.75)
            .frame(height: 34)
            .accessibilityAddTraits(.updatesFrequently)
    }

    private var messageColor: Color {
        switch session.tone {
        case .plain: return DS.textBody
        case .good:  return ChessMarkInk.ok
        case .bad:   return ChessInk.warn
        }
    }

    private var setsBar: some View {
        HStack(spacing: 5) {
            ForEach(Array(session.sets.enumerated()), id: \.offset) { index, set in
                ChessChip(text: Text(verbatim: set.title), isOn: index == session.setAt,
                          onFill: ChessMarkInk.askDeep, fontSize: 12,
                          cornerRadius: DS.smallRadius, lineLimit: 2) {
                    SoundManager.shared.playTap()
                    session.choose(set: index)
                }
            }
        }
    }

    private func palette(width: CGFloat) -> some View {
        HStack(spacing: 4) {
            ForEach(session.palette, id: \.self) { letter in
                if let first = letter.first, let piece = ChessPiece(fen: first) {
                    let left = session.left(of: letter)
                    ChessPaletteTile(piece: piece, isHeld: session.held == letter, count: left, height: 44) {
                        session.hold(letter)
                    }
                    .disabled(left <= 0)
                    .opacity(left <= 0 ? 0.4 : 1)
                }
            }
        }
        .frame(width: width)
    }

    // MARK: ボタン

    private func nextLessonButton(withTap: Bool = true) -> some View {
        ChessButton(label: "chess_next_lesson", isPrimary: true, height: 42) {
            if withTap { SoundManager.shared.playTap() }
            onOpen(session.index + 1)
        }
    }

    private var resetButton: some View {
        ChessButton(label: "chess_lesson_reset", height: 42) {
            SoundManager.shared.playTap()
            session.restart()
        }
    }

    @ViewBuilder
    private var controls: some View {
        HStack(spacing: 6) {
            if session.isDone && !session.isChase {
                resetButton
                if session.isLastTask {
                    if session.hasNextVolume {
                        ChessButton(label: "chess_next_volume", isPrimary: true, height: 42, action: onNextVolume)
                    } else if session.hasNext {
                        nextLessonButton(withTap: false)
                    }
                } else {
                    nextLessonButton()
                }
            } else if session.isReplay {
                ChessButton(label: "chess_back_move", disabled: !session.replayCanGoBack, height: 42) {
                    session.replayGo(-1)
                }
                // 最後まで見たら、「1手すすむ」の場所から次へ進める。もどって見直すこともできる
                if session.replayCanGoForward || !session.hasNext {
                    ChessButton(label: "chess_forward", isPrimary: true, disabled: !session.replayCanGoForward, height: 42) {
                        session.replayGo(1)
                    }
                } else {
                    nextLessonButton()
                }
            } else {
                ChessButton(label: "chess_undo", disabled: !session.canUndo, height: 42) { session.undo() }
                if session.canHint {
                    ChessButton(label: "chess_hint", disabled: session.isDone || session.hinted, height: 42) {
                        session.showHint()
                    }
                }
                resetButton
                if session.isDone && session.hasNext { nextLessonButton() }
            }
        }
    }
}
