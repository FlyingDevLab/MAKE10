//
//  ChessBoardView.swift
//  FDL-TenBlitz
//
//  盤と、チェスの画面で共通のボタン。「あそぶ」とレッスンの両方が使う。
//  盤は何を描くか（駒と印）を受け取るだけで、ルールも進行も知らない。
//
// ★ マスは Button ★
//   VoiceOver で 64 マスすべてに触れて、マスの名前を読み上げられるようにするため。
//

import SwiftUI

enum ChessMarkInk {
    static let goal   = Color(red: 0.604, green: 0.420, blue: 0.780)
    static let ask    = Color(red: 0.184, green: 0.620, blue: 0.561)
    static let askDeep = Color(red: 0.106, green: 0.420, blue: 0.376)
    static let lineLight = Color(red: 0.773, green: 0.639, blue: 0.745)
    static let lineDark  = Color(red: 0.647, green: 0.459, blue: 0.545)
    static let ok     = Color(red: 0.247, green: 0.561, blue: 0.227)
}

// MARK: - ボタン

struct ChessButton: View {
    let label: LocalizedStringKey
    var isPrimary = false
    var isWarning = false
    var disabled = false
    var height: CGFloat = 46
    let action: () -> Void

    private var fill: Color {
        if isWarning { return ChessInk.warn }
        return isPrimary ? ChessInk.frame : DS.choiceFill
    }

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .lineLimit(2)
                .minimumScaleFactor(0.65)
                .multilineTextAlignment(.center)
                .foregroundStyle(isPrimary || isWarning ? Color.white : DS.textPrimary)
                .padding(.horizontal, 6)
                .frame(maxWidth: .infinity)
                .frame(height: height)
                .background(RoundedRectangle(cornerRadius: DS.rowRadius).fill(fill))
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.4 : 1)
    }
}

// MARK: - 選ぶチップ

/// 切り替えのボタン。選んでいるものだけ色が付く。
struct ChessChip: View {
    let text: Text
    let isOn: Bool
    var onFill = ChessInk.frame
    var fontSize: CGFloat = 13
    var height: CGFloat = 34
    var cornerRadius = DS.rowRadius
    var lineLimit = 1
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            text
                .font(.system(size: fontSize, weight: .bold, design: .rounded))
                .lineLimit(lineLimit)
                .minimumScaleFactor(0.6)
                .multilineTextAlignment(.center)
                .foregroundStyle(isOn ? Color.white : DS.textPrimary)
                .padding(.horizontal, 3)
                .frame(maxWidth: .infinity)
                .frame(height: height)
                .background(RoundedRectangle(cornerRadius: cornerRadius).fill(isOn ? onFill : DS.choiceFill))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

// MARK: - 駒の棚

/// 並べる駒の棚の 1 つ。count があれば、あと何枚おけるかを添える。
struct ChessPaletteTile: View {
    let piece: ChessPiece
    let isHeld: Bool
    var count: Int?
    var height: CGFloat = 38
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 2) {
                ChessPieceView(piece: piece)
                if let count {
                    Text(verbatim: String(count))
                        .font(.system(size: 12, weight: .heavy, design: .rounded))
                        .foregroundStyle(DS.textPrimary)
                }
            }
            .padding(3)
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .background(RoundedRectangle(cornerRadius: DS.smallRadius).fill(isHeld ? ChessInk.pick : ChessInk.squareLight))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(verbatim: count.map { "\(piece.fen) \($0)" } ?? String(piece.fen)))
        .accessibilityAddTraits(isHeld ? .isSelected : [])
    }
}

// MARK: - 棋譜の行

/// 棋譜を 1 行で出す。新しい手が見えるように右端へ送る。選んでコピーできる。
struct ChessRecordLine: View {
    let text: String
    /// 手の数。増えたら右端へ送る
    let count: Int
    let width: CGFloat
    var fontSize: CGFloat = 13
    var height: CGFloat = 22

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                Text(verbatim: text.isEmpty ? " " : text)
                    .font(.system(size: fontSize, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(DS.muted)
                    .textSelection(.enabled)
                    .fixedSize()
                    .id("end")
            }
            .onChange(of: count) {
                proxy.scrollTo("end", anchor: .trailing)
            }
        }
        .frame(width: width, height: height)
    }
}

// MARK: - 盤

struct ChessBoardView: View {
    /// 64 マスの駒
    let pieces: [ChessPiece?]
    let marks: ChessBoardMarks
    var isFlipped = false
    let side: CGFloat
    /// プロモーションで選ぶ手。空でなければ盤の上に選ぶカードを出す
    var promotionChoices: [ChessMove] = []
    var onPromote: (ChessMove) -> Void = { _ in }
    let onTap: (Int) -> Void

    private let labelWidth: CGFloat = 16

    private var cell: CGFloat { floor((side - labelWidth * 2) / 8) }

    var body: some View {
        VStack(spacing: 0) {
            Color.clear.frame(width: cell * 8 + labelWidth * 2, height: 6)
            HStack(spacing: 0) {
                VStack(spacing: 0) {
                    ForEach(0..<8, id: \.self) { row in
                        let rank = isFlipped ? row + 1 : 8 - row
                        label(String(rank), isAsked: marks.askRanks.contains(rank)).frame(height: cell)
                    }
                }
                .frame(width: labelWidth)
                grid
                Color.clear.frame(width: labelWidth, height: 1)
            }
            HStack(spacing: 0) {
                ForEach(0..<8, id: \.self) { column in
                    let file = isFlipped ? 7 - column : column
                    label(String(Array("abcdefgh")[file]), isAsked: marks.askFiles.contains(file)).frame(width: cell)
                }
            }
            .frame(height: labelWidth)
        }
        .background(RoundedRectangle(cornerRadius: DS.rowRadius).fill(ChessInk.frame))
        .overlay {
            if !promotionChoices.isEmpty {
                ChessPromotionCard(choices: promotionChoices, cell: side / 9, onChoose: onPromote)
            }
        }
    }

    private func label(_ text: String, isAsked: Bool) -> some View {
        Text(verbatim: text)
            .font(.system(size: 11, weight: .bold, design: .rounded))
            .foregroundStyle(isAsked ? Color.white : ChessInk.frameInk)
            .frame(width: 15, height: 15)
            .background(Circle().fill(isAsked ? ChessMarkInk.askDeep : Color.clear))
            .accessibilityHidden(true)
    }

    private var grid: some View {
        VStack(spacing: 0) {
            ForEach(0..<8, id: \.self) { row in
                HStack(spacing: 0) {
                    ForEach(0..<8, id: \.self) { column in
                        let index = row * 8 + column
                        let square = isFlipped ? 63 - index : index
                        ChessSquareView(square: square, piece: pieces[square], marks: marks, cell: cell) {
                            onTap(square)
                        }
                    }
                }
            }
        }
    }
}

private struct ChessSquareView: View {
    let square: Int
    let piece: ChessPiece?
    let marks: ChessBoardMarks
    let cell: CGFloat
    let onTap: () -> Void

    private var isLight: Bool { ChessSquare.isLight(square) }

    var body: some View {
        Button(action: onTap) {
            ZStack {
                Rectangle().fill(background)
                if let piece {
                    ChessPieceView(piece: piece).frame(width: cell * 0.86, height: cell * 0.86)
                }
                if marks.goal.contains(square) {
                    Circle()
                        .strokeBorder(ChessMarkInk.goal, style: StrokeStyle(lineWidth: 2.5, dash: [4, 3]))
                        .padding(cell * 0.06)
                }
                if marks.ask.contains(square) {
                    Rectangle().strokeBorder(ChessMarkInk.ask, lineWidth: 3)
                }
                if marks.goto.contains(square) {
                    if piece == nil {
                        Circle().fill(ChessInk.goto.opacity(0.75)).frame(width: cell * 0.28, height: cell * 0.28)
                    } else {
                        Circle().stroke(ChessInk.goto.opacity(0.85), lineWidth: cell * 0.07).padding(cell * 0.05)
                    }
                }
                if marks.pick == square {
                    Rectangle().strokeBorder(ChessInk.pick, lineWidth: 3)
                } else if marks.check == square {
                    Rectangle().strokeBorder(ChessInk.warn, lineWidth: 3)
                } else if marks.hint == square {
                    Rectangle().strokeBorder(ChessMarkInk.ask, lineWidth: 4)
                } else if marks.wrong == square {
                    Rectangle().fill(ChessInk.warn.opacity(0.35))
                }
                if marks.hit.contains(square) {
                    Text(verbatim: "✓")
                        .font(.system(size: cell * 0.3, weight: .black, design: .rounded))
                        .foregroundStyle(ChessMarkInk.ok)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                        .padding(.trailing, 2)
                }
            }
            .frame(width: cell, height: cell)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(verbatim: spoken))
        .accessibilityAddTraits(marks.pick == square ? .isSelected : [])
    }

    private var background: Color {
        if marks.line.contains(square) { return isLight ? ChessMarkInk.lineLight : ChessMarkInk.lineDark }
        if marks.last.contains(square) { return isLight ? ChessInk.lastLight : ChessInk.lastDark }
        return isLight ? ChessInk.squareLight : ChessInk.squareDark
    }

    /// 駒の記号。[色 × 6 + 種類]
    private static let symbols = Array("♙♘♗♖♕♔♟♞♝♜♛♚")

    /// 読み上げ。マスの名前と、駒の記号。記号は読み上げ機能が各言語で駒の名前にしてくれる。
    private var spoken: String {
        let name = ChessSquare.name(square)
        guard let piece else { return name }
        return "\(name) \(Self.symbols[Int(piece.color.rawValue) * 6 + Int(piece.type.rawValue)])"
    }
}

// MARK: - プロモーション

private struct ChessPromotionCard: View {
    let choices: [ChessMove]
    let cell: CGFloat
    let onChoose: (ChessMove) -> Void

    var body: some View {
        VStack(spacing: 8) {
            Text("chess_promote")
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(DS.textPrimary)
            HStack(spacing: 6) {
                ForEach(choices, id: \.self) { move in
                    if let type = move.promotion {
                        Button { onChoose(move) } label: {
                            ChessPieceView(piece: ChessPiece(type, move.piece.color))
                                .frame(width: cell * 1.1, height: cell * 1.1)
                                .background(RoundedRectangle(cornerRadius: DS.smallRadius).fill(ChessInk.squareLight))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(Text(verbatim: String(type.letter)))
                    }
                }
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: DS.sectionRadius).fill(DS.card).shadow(radius: 6))
    }
}
