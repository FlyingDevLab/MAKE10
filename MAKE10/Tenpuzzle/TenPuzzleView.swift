//
//  TenPuzzleView.swift
//  FDL-TenBlitz
//
//  Created by 空飛ぶ研究室(FlyingDevLab) on 2026/06/13.
//

// 四則演算テンパズルのUI全体を担うファイル。
//
// ★ このファイルの構成 ★
//   TenPuzzleView        … ルートView
//   TenPuzzleHomeView    … モード（A/B/C）を選ぶ画面
//   TenPuzzleGameView    … 実際にパズルを解く画面
//   TenPuzzleResultView  … セッション終了後の結果画面
//   ─ ゲーム画面のパーツ（private）─────────────────────────
//   DigitTileRow         … 4枚の数字タイル（タップで式に追加）
//   HintBanner           … ヒント表示バナー（答えをバナーで見せる）
//   ExpressionDisplay    … 組み立て中の式・途中計算・フィードバック
//   OperatorKeyboard     … 演算子・括弧・削除ボタン
//   SubmitArea           … 提出 / ヒント / 「作れない！」ボタン

import SwiftUI

// MARK: - TenPuzzleView（ルート）

struct TenPuzzleView: View {

    @State private var viewModel = TenPuzzleViewModel()

    var body: some View {
        ZStack {
            switch viewModel.phase {
            case .home:
                TenPuzzleHomeView(viewModel: viewModel)
                    .transition(.opacity)
            case .playing:
                TenPuzzleGameView(viewModel: viewModel)
                    .transition(.opacity)
            case .result:
                TenPuzzleResultView(viewModel: viewModel)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: viewModel.phase)
        .onAppear    { viewModel.resume()  }
        .onDisappear { viewModel.suspend() }
        .onReceive(NotificationCenter.default.publisher(
            for: UIApplication.didEnterBackgroundNotification)
        ) { _ in viewModel.suspend() }
        .onReceive(NotificationCenter.default.publisher(
            for: UIApplication.willEnterForegroundNotification)
        ) { _ in viewModel.resume() }
    }
}

// MARK: - TenPuzzleHomeView（モード選択）

private struct TenPuzzleHomeView: View {

    var viewModel: TenPuzzleViewModel

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 6) {
                Text("🔢")
                    .font(.system(size: 56))
                Text("四則演算テンパズル")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(DS.textPrimary)
                Text("4つの数字で10を作ろう！")
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(DS.muted)
            }
            .padding(.bottom, 36)

            VStack(spacing: 14) {
                ForEach(TenPuzzleMode.allCases, id: \.rawValue) { mode in
                    ModeCard(mode: mode) {
                        SoundManager.shared.vibrate()
                        SoundManager.shared.playTap()
                        viewModel.startSession(mode: mode)
                    }
                }
            }
            .padding(.horizontal, 24)

            Spacer()
        }
    }
}

private struct ModeCard: View {
    let mode:  TenPuzzleMode
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 16) {
                Text(mode.icon)
                    .font(.system(size: 28))

                VStack(alignment: .leading, spacing: 4) {
                    Text(mode.title)
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundStyle(DS.textPrimary)
                    Text(mode.subtitle)
                        .font(.system(size: 12, weight: .regular, design: .rounded))
                        .foregroundStyle(DS.muted)
                        .multilineTextAlignment(.leading)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(mode.color.opacity(0.6))
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: DS.tagRadius)
                    .fill(mode.color.opacity(0.08))
                    .overlay(
                        RoundedRectangle(cornerRadius: DS.tagRadius)
                            .stroke(mode.color.opacity(0.25), lineWidth: 1.5)
                    )
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - TenPuzzleGameView（メインゲーム）

private struct TenPuzzleGameView: View {

    var viewModel: TenPuzzleViewModel

    var body: some View {
        VStack(spacing: 0) {
            // 問題カウンター
            ProblemCounter(
                current: viewModel.problemNumber,
                total:   TenPuzzleMode.problemsPerSession,
                mode:    viewModel.selectedMode
            )
            .padding(.horizontal, 24)
            .padding(.top, 8)
            .padding(.bottom, 4)

            // 数字タイル（4枚）
            if let problem = viewModel.currentProblem {
                DigitTileRow(
                    digits:    problem.digits,
                    usedSlots: viewModel.usedSlots,
                    lastIsDigit: viewModel.tokens.last?.isDigit == true,
                    onTap:     { slot in viewModel.tapDigit(slot: slot) }
                )
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 8)
            }

            // ヒントバナー（ヒントボタンを押したときだけ表示）
            if let hint = viewModel.hintBannerText {
                HintBanner(text: hint)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 8)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            // 式の表示エリア
            ExpressionDisplay(
                tokens:    viewModel.tokens,
                judgment:  viewModel.lastJudgment,
                state:     viewModel.problemState,
                shownHint: viewModel.shownHint,
                liveValue: viewModel.liveValue
            )
            .padding(.horizontal, 20)
            .padding(.bottom, 12)

            // 演算子キーボード
            OperatorKeyboard(
                onOp:     { op in viewModel.tapOperator(op) },
                onParen:  { p  in viewModel.tapParen(p)    },
                onDelete: { viewModel.deleteLastToken()     },
                onReset:  { viewModel.resetExpression()     },
                disabled: viewModel.problemState != .solving
            )
            .padding(.horizontal, 20)
            .padding(.bottom, 12)

            // 提出・アクションエリア
            SubmitArea(viewModel: viewModel)
                .padding(.horizontal, 20)

            Spacer(minLength: 0)
        }
        .animation(.easeInOut(duration: 0.25), value: viewModel.hintShown)
    }
}

// MARK: - 問題カウンター

private struct ProblemCounter: View {
    let current: Int
    let total:   Int
    let mode:    TenPuzzleMode

    var body: some View {
        HStack {
            HStack(spacing: 2) {
                Text("\(current)")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(mode.color)
                Text("/ \(total)")
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(DS.muted)
            }

            Spacer()

            Text(mode.title)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(mode.color)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(mode.color.opacity(0.1), in: Capsule())
        }
    }
}

// MARK: - 数字タイル行

private struct DigitTileRow: View {
    let digits:      [Int]
    let usedSlots:   Set<Int>
    let lastIsDigit: Bool  // 直前のトークンが数字かどうか（結合防止のグレーアウト用）
    let onTap:       (Int) -> Void

    var body: some View {
        HStack(spacing: 10) {
            ForEach(0..<digits.count, id: \.self) { slot in
                DigitTile(
                    value:   digits[slot],
                    isUsed:  usedSlots.contains(slot),
                    blocked: !usedSlots.contains(slot) && lastIsDigit,
                    onTap:   { onTap(slot) }
                )
            }
        }
    }
}

/// 数字タイル1枚。
/// - isUsed:  使用済み（グレーアウト、タップ不可）
/// - blocked: 直前が数字のため結合防止でタップ不可（薄くオレンジで警告）
private struct DigitTile: View {
    let value:   Int
    let isUsed:  Bool
    let blocked: Bool  // 数字の結合を防ぐための一時ブロック
    let onTap:   () -> Void

    private var isDisabled: Bool { isUsed || blocked }

    var body: some View {
        Button(action: onTap) {
            Text("\(value)")
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .foregroundStyle(
                    isUsed  ? DS.muted.opacity(0.4) :
                    blocked ? DS.gaugeWarn.opacity(0.5) :
                    DS.textPrimary
                )
                .frame(maxWidth: .infinity)
                .frame(height: 76)
                .background(
                    RoundedRectangle(cornerRadius: DS.btnRadius)
                        .fill(
                            isUsed  ? DS.muted.opacity(0.06) :
                            blocked ? DS.gaugeWarn.opacity(0.05) :
                            DS.choiceFill
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: DS.btnRadius)
                                .stroke(
                                    isUsed  ? DS.muted.opacity(0.1) :
                                    blocked ? DS.gaugeWarn.opacity(0.25) :
                                    DS.muted.opacity(0.18),
                                    lineWidth: 1.5
                                )
                        )
                )
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .animation(.easeInOut(duration: 0.12), value: isDisabled)
    }
}

// MARK: - ヒントバナー

/// ヒントボタンを押したときに表示されるバナー。
/// 解ける問題なら解の例、不可能問題なら「作れません」メッセージを表示する。
private struct HintBanner: View {
    let text: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "lightbulb.fill")
                .foregroundStyle(.orange)
                .font(.system(size: 15))

            Text(text)
                .font(.system(size: 15, weight: .bold, design: .monospaced))
                .foregroundStyle(DS.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: DS.tagRadius)
                .fill(Color.orange.opacity(0.10))
                .overlay(
                    RoundedRectangle(cornerRadius: DS.tagRadius)
                        .stroke(Color.orange.opacity(0.3), lineWidth: 1.2)
                )
        )
    }
}

// MARK: - 式の表示エリア

/// 状態に応じて表示を切り替える：
///   .declared          → 「宣言不正解」解の表示（ExpressionDisplay 内）
///   .correct / .wrong  → 正解・不正解フィードバック
///   tokens が空         → プレースホルダー
///   tokens あり         → トークン + 途中計算値（liveValue）
private struct ExpressionDisplay: View {
    let tokens:    [ExprToken]
    let judgment:  TenPuzzleJudgment?
    let state:     TenPuzzleProblemState
    let shownHint: String?   // .declared 時のみ non-nil
    let liveValue: Double?

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: DS.tagRadius)
                .fill(bgColor)
                .overlay(
                    RoundedRectangle(cornerRadius: DS.tagRadius)
                        .stroke(borderColor, lineWidth: 1.5)
                )

            Group {
                if state == .declared, let hint = shownHint {
                    // 「作れない！」宣言が不正解だったとき：解を表示
                    VStack(spacing: 3) {
                        Text("作れます！")
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundStyle(DS.muted)
                        Text(hint)
                            .font(.system(size: 18, weight: .bold, design: .monospaced))
                            .foregroundStyle(DS.textPrimary)
                    }

                } else if state == .correct || state == .wrong {
                    HStack(spacing: 8) {
                        Text(state == .correct ? "⭕️" : "❌")
                            .font(.system(size: 28))
                        if let j = judgment {
                            Text(j.message)
                                .font(.system(size: 16, weight: .bold, design: .rounded))
                                .foregroundStyle(j.color)
                        }
                    }

                } else if tokens.isEmpty {
                    Text("数字タイルをタップして式を作ろう")
                        .font(.system(size: 13, weight: .regular, design: .rounded))
                        .foregroundStyle(DS.muted.opacity(0.6))

                } else {
                    // 式トークン + 右端に途中計算値
                    HStack(spacing: 0) {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 4) {
                                ForEach(tokens) { token in
                                    TokenChip(token: token)
                                }
                                CursorView()
                            }
                            .padding(.horizontal, 12)
                        }

                        if let val = liveValue {
                            Text("= \(formatLiveValue(val))")
                                .font(.system(size: 14, weight: .bold, design: .monospaced))
                                .foregroundStyle(
                                    abs(val - 10) < 1e-9 ? DS.gaugeFull : DS.muted.opacity(0.7)
                                )
                                .padding(.trailing, 12)
                                .lineLimit(1)
                        }
                    }
                }
            }
        }
        .frame(height: 68)
        .animation(.easeInOut(duration: 0.2), value: state)
    }

    private var bgColor: Color {
        switch state {
        case .correct:          return DS.gaugeFull.opacity(0.08)
        case .wrong, .declared: return DS.gaugeWarn.opacity(0.08)
        default:                return DS.choiceFill
        }
    }

    private var borderColor: Color {
        switch state {
        case .correct:          return DS.gaugeFull.opacity(0.4)
        case .wrong, .declared: return DS.gaugeWarn.opacity(0.4)
        default:                return DS.muted.opacity(0.15)
        }
    }

    private func formatLiveValue(_ val: Double) -> String {
        let rounded = val.rounded()
        if abs(val - rounded) < 1e-9 { return "\(Int(rounded))" }
        return String(format: "%.3g", val)
    }
}

private struct TokenChip: View {
    let token: ExprToken

    private var bg: Color {
        if case .digit = token.type { return DS.primary.opacity(0.12) }
        return DS.muted.opacity(0.10)
    }

    var body: some View {
        Text(token.displayText)
            .font(.system(size: 22, weight: token.isDigit ? .bold : .medium, design: .rounded))
            .foregroundStyle(token.isDigit ? DS.primary : DS.textPrimary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(bg, in: RoundedRectangle(cornerRadius: 6))
    }
}

private struct CursorView: View {
    @State private var visible = true

    var body: some View {
        Rectangle()
            .fill(DS.primary.opacity(0.6))
            .frame(width: 2, height: 24)
            .opacity(visible ? 1 : 0)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.5).repeatForever()) {
                    visible.toggle()
                }
            }
    }
}

// MARK: - 演算子キーボード

private struct OperatorKeyboard: View {
    let onOp:    (String) -> Void
    let onParen: (String) -> Void
    let onDelete: () -> Void
    let onReset:  () -> Void
    let disabled: Bool

    private let row1 = ["+", "−", "×", "÷"]

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                ForEach(row1, id: \.self) { op in
                    KeyboardButton(label: op, color: DS.primary.opacity(0.8)) { onOp(op) }
                }
            }

            HStack(spacing: 8) {
                KeyboardButton(label: "(", color: DS.muted.opacity(0.6)) { onParen("(") }
                KeyboardButton(label: ")", color: DS.muted.opacity(0.6)) { onParen(")") }

                Button(action: onDelete) {
                    Image(systemName: "delete.left")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(DS.textPrimary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(DS.muted.opacity(0.10), in: RoundedRectangle(cornerRadius: DS.tagRadius))
                }
                .buttonStyle(.plain)
                .disabled(disabled)

                Button(action: onReset) {
                    Text("リセット")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(DS.gaugeWarn.opacity(0.85))
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(DS.gaugeWarn.opacity(0.08), in: RoundedRectangle(cornerRadius: DS.tagRadius))
                }
                .buttonStyle(.plain)
                .disabled(disabled)
            }
        }
        .opacity(disabled ? 0.45 : 1.0)
        .animation(.easeInOut(duration: 0.15), value: disabled)
    }
}

private struct KeyboardButton: View {
    let label:  String
    let color:  Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(color)
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .background(color.opacity(0.10), in: RoundedRectangle(cornerRadius: DS.tagRadius))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 提出エリア

/// ボタン構成:
///   [= 10？ こたえる]          … 全モード共通
///   [ヒント] （+ [作れない！]） … ヒント全モード共通、作れない！はモードCのみ
private struct SubmitArea: View {
    var viewModel: TenPuzzleViewModel

    private var isSolving: Bool { viewModel.problemState == .solving }
    private var canSubmit: Bool { isSolving && !viewModel.tokens.isEmpty }

    var body: some View {
        VStack(spacing: 10) {
            // こたえるボタン
            Button {
                withAnimation(.spring(response: 0.28, dampingFraction: 0.75)) {
                    viewModel.submitExpression()
                }
            } label: {
                Text("= 10？　こたえる")
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 54)
                    .background(
                        RoundedRectangle(cornerRadius: DS.btnRadius)
                            .fill(canSubmit ? DS.primary : DS.muted.opacity(0.3))
                    )
            }
            .buttonStyle(.plain)
            .disabled(!canSubmit)
            .animation(.easeInOut(duration: 0.15), value: canSubmit)

            // サブボタン行
            HStack(spacing: 10) {
                // ヒントボタン（全モード共通）
                // ヒントを見たあとはグレーアウト（2回押し防止）
                ActionButton(
                    label:    viewModel.hintShown ? "ヒント表示中" : "ヒント",
                    icon:     "lightbulb",
                    color:    .orange,
                    action:   { viewModel.showHint() },
                    disabled: !isSolving || viewModel.hintShown
                )

                // 「作れない！」ボタン（モードCのみ）
                if viewModel.selectedMode == .modeC {
                    ActionButton(
                        label:    "作れない！",
                        icon:     "xmark.circle",
                        color:    DS.gaugeWarn,
                        action:   { viewModel.declareImpossible() },
                        disabled: !isSolving
                    )
                }
            }
        }
    }
}

private struct ActionButton: View {
    let label:    String
    let icon:     String
    let color:    Color
    let action:   () -> Void
    let disabled: Bool

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .medium))
                Text(label)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
            }
            .foregroundStyle(color)
            .frame(maxWidth: .infinity)
            .frame(height: 44)
            .background(color.opacity(disabled ? 0.05 : 0.10), in: RoundedRectangle(cornerRadius: DS.tagRadius))
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.5 : 1.0)
        .animation(.easeInOut(duration: 0.15), value: disabled)
    }
}

// MARK: - TenPuzzleResultView（結果画面）

private struct TenPuzzleResultView: View {

    var viewModel: TenPuzzleViewModel

    private var record: TenPuzzleSessionRecord { viewModel.record }
    private var mode:   TenPuzzleMode           { viewModel.selectedMode }

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 20) {
                VStack(spacing: 6) {
                    Text(resultEmoji)
                        .font(.system(size: 60))
                    Text("\(record.correct) / \(record.total)")
                        .font(.system(size: 52, weight: .black, design: .rounded))
                        .foregroundStyle(mode.color)
                    Text("正解")
                        .font(.system(size: 18, weight: .medium, design: .rounded))
                        .foregroundStyle(DS.muted)
                }

                VStack(spacing: 8) {
                    switch mode {
                    case .modeA:
                        if record.hintUsed > 0 {
                            ResultRow(label: "ヒントを使って正解", value: "\(record.hintUsed)問")
                        }
                    case .modeB:
                        ResultRow(label: "ヒントなしで正解", value: "\(record.selfSolved)問")
                        ResultRow(label: "ヒントを使って正解", value: "\(record.hintUsed)問")
                    case .modeC:
                        ResultRow(label: "自力で正解",           value: "\(record.correct - record.impossible)問")
                        ResultRow(label: "「作れない！」で正解", value: "\(record.impossible)問")
                        if record.hintUsed > 0 {
                            ResultRow(label: "ヒントを使用",     value: "\(record.hintUsed)問")
                        }
                    }
                }
                .padding(.horizontal, 8)
            }
            .padding(28)
            .background(DS.cardShadow())

            Spacer()

            VStack(spacing: 12) {
                Button {
                    SoundManager.shared.vibrate()
                    SoundManager.shared.playTap()
                    viewModel.startSession(mode: mode)
                } label: {
                    Text("もう一度")
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 54)
                        .background(mode.color, in: RoundedRectangle(cornerRadius: DS.btnRadius))
                }
                .buttonStyle(.plain)

                Button {
                    SoundManager.shared.vibrate()
                    SoundManager.shared.playTap()
                    viewModel.returnToHome()
                } label: {
                    Text("モード選択に戻る")
                        .font(.system(size: 15, weight: .medium, design: .rounded))
                        .foregroundStyle(DS.muted)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 24)
        }
    }

    private var resultEmoji: String {
        let ratio = Double(record.correct) / Double(record.total)
        switch ratio {
        case 1.0:    return "🏆"
        case 0.8...: return "🎉"
        case 0.6...: return "😊"
        case 0.4...: return "🙂"
        default:     return "💪"
        }
    }
}

private struct ResultRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .font(.system(size: 14, weight: .regular, design: .rounded))
                .foregroundStyle(DS.muted)
            Spacer()
            Text(value)
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(DS.textPrimary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(DS.choiceFill, in: RoundedRectangle(cornerRadius: 10))
    }
}
