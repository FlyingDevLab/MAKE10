//
//  ChessPieceView.swift
//  FDL-TenBlitz
//
//  駒の絵。Web 版の SVG と同じ形を、ここで描いている。
//
// ★ Unicode のチェス記号（♔♕♖）を使わない理由（Web 版と同じ）★
//   ・白の駒が輪郭だけの字になり、白いマスの上で読み取りにくい
//   ・環境によって形が大きく変わる。絵文字として描く環境もある
//
// ★ 画像ではなくパスで持つ理由 ★
//   同じ型紙を白と黒の両方で使い、色をコードで決められる。画像は 1 枚も増えない。
//   座標は Web 版と同じ 100 × 100 で、どの駒も底辺を y = 85 に揃えてある。
//

import SwiftUI

enum ChessInk {
    static let squareLight = Color(red: 0.941, green: 0.859, blue: 0.714)
    static let squareDark  = Color(red: 0.690, green: 0.498, blue: 0.310)
    static let lastLight   = Color(red: 0.882, green: 0.784, blue: 0.553)
    static let lastDark    = Color(red: 0.722, green: 0.549, blue: 0.306)
    static let frame       = Color(red: 0.420, green: 0.278, blue: 0.157)
    static let frameInk    = Color(red: 0.953, green: 0.894, blue: 0.800)
    static let pick        = Color(red: 0.914, green: 0.769, blue: 0.416)
    static let goto        = Color(red: 0.302, green: 0.502, blue: 0.820)
    static let warn        = Color(red: 0.753, green: 0.263, blue: 0.173)
    static let whiteFill   = Color(red: 0.992, green: 0.980, blue: 0.957)
    static let whiteLine   = Color(red: 0.275, green: 0.188, blue: 0.110)
    static let blackFill   = Color(red: 0.192, green: 0.153, blue: 0.133)
    static let blackLine   = Color(red: 0.063, green: 0.043, blue: 0.027)
    static let blackEye    = Color(red: 0.643, green: 0.565, blue: 0.486)
}

// MARK: - 型紙

private struct ChessGlyph {
    enum Kind { case body, line, eye }
    let parts: [(kind: Kind, path: Path)]

    private static func svg(_ text: String) -> Path { ChessSVGPath.parse(text) }

    private static func circle(_ x: CGFloat, _ y: CGFloat, _ r: CGFloat) -> Path {
        Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2))
    }

    private static func bar(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ r: CGFloat) -> Path {
        Path(roundedRect: CGRect(x: x, y: y, width: w, height: h), cornerRadius: r)
    }

    private static func make(_ type: ChessPieceType) -> ChessGlyph {
        switch type {
        case .pawn:
            return ChessGlyph(parts: [
                (.body, circle(50, 31, 12.5)),
                (.body, svg("M38 44h24l-3.5 8.5c0 9 5 15.5 8 21.5H33.5c3-6 8-12.5 8-21.5z")),
                (.body, bar(28, 74, 44, 11, 4.5)),
            ])
        case .rook:
            return ChessGlyph(parts: [
                (.body, svg("M27 19h11v9h8v-9h8v9h8v-9h11v19l-7 5v22l7 9H27l7-9V43l-7-5z")),
                (.body, bar(23, 75, 54, 10, 4)),
            ])
        case .knight:
            return ChessGlyph(parts: [
                (.body, svg("M64 12c-1.5 5.5-5.5 8.5-11 10.5-7 2.5-13.5 7-18.5 13.5-3.5 4.5-6.5 9.5-6.5 13.5 0 4.5 3.5 6.5 7 5 3-1.5 4.5-4.5 7.5-6 2.5-1.5 5 0 4.5 2.5-1 6-5 10.5-8.5 15-4 5-7 9.5-7.5 15h47c1.5-13 2-25.5-1.5-35.5-2.5-7-6.5-12-10-16.5-2-3-2.5-10 0-16.5z")),
                (.eye, circle(51, 29, 2.6)),
                (.body, bar(26, 75, 48, 10, 4)),
            ])
        case .bishop:
            return ChessGlyph(parts: [
                (.body, circle(50, 16, 5.5)),
                (.body, svg("M50 24c-10 6-17.5 15.5-17.5 25.5 0 7 4 12.5 8.5 15.5h18c4.5-3 8.5-9 8.5-15.5C67.5 39.5 60 30 50 24z")),
                (.line, svg("M50 32v15M43 39.5h14")),
                (.body, bar(32, 64, 36, 7.5, 3.5)),
                (.body, bar(26, 75, 48, 10, 4)),
            ])
        case .queen:
            return ChessGlyph(parts: [
                (.body, svg("M20 32l7.5 22h45L80 32 66 42.5 58 26l-8 16.5L42 26l-8 16.5z")),
                (.body, circle(20, 29, 4.5)),
                (.body, circle(35, 26, 4.5)),
                (.body, circle(50, 22.5, 5)),
                (.body, circle(65, 26, 4.5)),
                (.body, circle(80, 29, 4.5)),
                (.body, svg("M28 57h44l-4 17H32z")),
                (.body, bar(26, 75, 48, 10, 4)),
            ])
        case .king:
            return ChessGlyph(parts: [
                (.body, svg("M45.5 7h9v7.5h7.5v9h-7.5V31h-9v-7.5H38v-9h7.5z")),
                (.body, svg("M26 38c7-6 16-9.5 24-9.5S67 32 74 38l-5 19H31z")),
                (.body, bar(28, 59, 44, 7.5, 3.5)),
                (.body, svg("M31 69h38l-2 5H33z")),
                (.body, bar(26, 75, 48, 10, 4)),
            ])
        }
    }

    static let all: [ChessPieceType: ChessGlyph] = Dictionary(
        uniqueKeysWithValues: ChessPieceType.allCases.map { ($0, make($0)) })
}

/// SVG の path の文字を Path にする。駒の型紙で使う命令だけ読む。
private enum ChessSVGPath {

    private static func tokens(_ text: String) -> [String] {
        var out: [String] = []
        var number = ""
        for ch in text {
            if ch.isLetter {
                if !number.isEmpty { out.append(number); number = "" }
                out.append(String(ch))
            } else if ch == "-" {
                if !number.isEmpty { out.append(number) }
                number = "-"
            } else if ch == " " || ch == "," {
                if !number.isEmpty { out.append(number); number = "" }
            } else if ch == "." && number.contains(".") {
                out.append(number)
                number = "."
            } else {
                number.append(ch)
            }
        }
        if !number.isEmpty { out.append(number) }
        return out
    }

    static func parse(_ text: String) -> Path {
        var path = Path()
        let list = tokens(text)
        var index = 0
        var current = CGPoint.zero
        var start = CGPoint.zero
        var control = CGPoint.zero
        var command: Character = "M"

        func number() -> CGFloat {
            defer { index += 1 }
            return CGFloat(Double(list[index]) ?? 0)
        }
        func point(relative: Bool) -> CGPoint {
            let x = number(), y = number()
            return relative ? CGPoint(x: current.x + x, y: current.y + y) : CGPoint(x: x, y: y)
        }

        while index < list.count {
            if let ch = list[index].first, ch.isLetter {
                command = ch
                index += 1
                if ch == "z" || ch == "Z" {
                    path.closeSubpath()
                    current = start
                    continue
                }
            }
            let relative = command.isLowercase
            switch Character(command.uppercased()) {
            case "M":
                current = point(relative: relative)
                start = current
                path.move(to: current)
                command = relative ? "l" : "L"   // 続く数字は線になる
            case "L":
                current = point(relative: relative)
                path.addLine(to: current)
            case "H":
                let x = number()
                current.x = relative ? current.x + x : x
                path.addLine(to: current)
            case "V":
                let y = number()
                current.y = relative ? current.y + y : y
                path.addLine(to: current)
            case "C":
                let first = point(relative: relative)
                let second = point(relative: relative)
                let end = point(relative: relative)
                path.addCurve(to: end, control1: first, control2: second)
                control = second
                current = end
            case "S":
                let first = CGPoint(x: current.x * 2 - control.x, y: current.y * 2 - control.y)
                let second = point(relative: relative)
                let end = point(relative: relative)
                path.addCurve(to: end, control1: first, control2: second)
                control = second
                current = end
            default:
                return path
            }
        }
        return path
    }
}

// MARK: - 駒

struct ChessPieceView: View {
    let piece: ChessPiece

    var body: some View {
        Canvas { context, size in
            guard let glyph = ChessGlyph.all[piece.type] else { return }
            context.scaleBy(x: size.width / 100, y: size.height / 100)
            let isWhite = piece.color == .white
            let fill = isWhite ? ChessInk.whiteFill : ChessInk.blackFill
            let line = isWhite ? ChessInk.whiteLine : ChessInk.blackLine
            let stroke = StrokeStyle(lineWidth: 3.4, lineCap: .round, lineJoin: .round)
            for part in glyph.parts {
                switch part.kind {
                case .body:
                    context.fill(part.path, with: .color(fill))
                    context.stroke(part.path, with: .color(line), style: stroke)
                case .line:
                    context.stroke(part.path, with: .color(line), style: stroke)
                case .eye:
                    context.fill(part.path, with: .color(isWhite ? ChessInk.whiteLine : ChessInk.blackEye))
                }
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityHidden(true)
    }
}
