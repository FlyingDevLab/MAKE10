//
//  TenPuzzleView.swift
//  FDL-TenBlitz
//
//  Created by 空飛ぶ研究室(FlyingDevLab) on 2026/06/13.
//

// 四則演算テンパズルのUI全体を担うファイル。
// TenPuzzleView がルートとなり、ViewModel.phase に応じて以下の画面を切り替える。
//   .home    → TenPuzzleHomeView（モード選択画面）
//   .playing → TenPuzzleGameView（メインのゲーム画面）
//   .result  → TenPuzzleResultView（結果画面）
//
// ★ このファイルの構成 ★
//   TenPuzzleView        … ルートView（フェーズで画面を切り替える）
//   TenPuzzleHomeView    … モード（A/B/C）を選ぶ画面
//   TenPuzzleGameView    … 実際にパズルを解く画面
//   TenPuzzleResultView  … セッション終了後の結果画面
//   ─ ゲーム画面のパーツ（private）─────────────────────────────
//   DigitTileRow         … 4枚の数字タイル（タップで式に追加）
//   ExpressionDisplay    … 組み立て中の式を表示するエリア
//   OperatorKeyboard     … 演算子・括弧・削除ボタンの段
//   SubmitArea           … 提出ボタン（＋モードB/Cのサブボタン）

import SwiftUI

// MARK: - TenPuzzleView（ルート）

/// 四則演算テンパズルのルートView。JankenViewと同じ構造。
/// ViewModel.phase を監視し、フェーズに応じた子Viewを表示する。
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
        // アプリがバックグラウンドに入ったとき / フォアグラウンドに戻ったとき
        // モードCのタイマーを正確に停止・再開するために通知を購読する
        .onReceive(NotificationCenter.default.publisher(
            for: UIApplication.didEnterBackgroundNotification)
        ) { _ in viewModel.suspend() }
        .onReceive(NotificationCenter.default.publisher(
            for: UIApplication.willEnterForegroundNotification)
        ) { _ in viewModel.resume() }
    }
}

// MARK: - TenPuzzleHomeView（モード選択）

/// 3つのモード（A/B/C）を選ぶ画面。
/// 各モードカードをタップするとそのモードでセッションが始まる。
private struct TenPuzzleHomeView: View {

    var viewModel: TenPuzzleViewModel

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            // タイトル
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

            // モード選択カード
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

/// モード選択カード（タップでそのモードを開始）
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
                    // subtitle を使う（description は CustomStringConvertible と衝突するため）
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

/// パズルを実際に解く画面。
/// 上から：問題カウンター → 数字タイル → 式表示 → キーボード → 提出エリア
private struct TenPuzzleGameView: View {

    var viewModel: TenPuzzleViewModel

    var body: some View {
        VStack(spacing: 0) {
            // ── 問題カウンター ─────────────────────────────────
            ProblemCounter(
                current: viewModel.problemNumber,
                total:   TenPuzzleMode.problemsPerSession,
                mode:    viewModel.selectedMode
            )
            .padding(.horizontal, 24)
            .padding(.top, 8)
            .padding(.bottom, 4)

            // ── モードCのタイマー ──────────────────────────────
            if viewModel.selectedMode == .modeC {
                TimerBar(
                    timeRemaining: viewModel.timeRemaining,
                    totalTime:     viewModel.selectedMode.timerSeconds ?? 45
                )
                .padding(.horizontal, 24)
                .padding(.bottom, 8)
            }

            // ── 数字タイル（4枚）─────────────────────────────
            if let problem = viewModel.currentProblem {
                DigitTileRow(
                    digits:    problem.digits,
                    usedSlots: viewModel.usedSlots,
                    onTap:     { slot in viewModel.tapDigit(slot: slot) }
                )
                .padding(.horizontal, 20)
                .padding(.vertical, 12)

                // ── 式の表示エリア ───────────────────────────
                ExpressionDisplay(
                    tokens:    viewModel.tokens,
                    judgment:  viewModel.lastJudgment,
                    state:     viewModel.problemState,
                    shownHint: viewModel.shownHint
                )
                .padding(.horizontal, 20)
                .padding(.bottom, 12)
            }

            // ── 演算子キーボード ───────────────────────────────
            OperatorKeyboard(
                onOp:     { op in viewModel.tapOperator(op) },
                onParen:  { p  in viewModel.tapParen(p)    },
                onDelete: { viewModel.deleteLastToken()     },
                onReset:  { viewModel.resetExpression()     },
                disabled: viewModel.problemState != .solving
            )
            .padding(.horizontal, 20)
            .padding(.bottom, 12)

            // ── 提出・アクションエリア ────────────────────────
            SubmitArea(viewModel: viewModel)
                .padding(.horizontal, 20)

            Spacer(minLength: 0)
        }
    }
}

// MARK: - 問題カウンター

private struct ProblemCounter: View {
    let current: Int
    let total:   Int
    let mode:    TenPuzzleMode

    var body: some View {
        HStack {
            // 問題番号（N / 10）
            HStack(spacing: 2) {
                Text("\(current)")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(mode.color)
                Text("/ \(total)")
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(DS.muted)
            }

            Spacer()

            // モードラベル
            Text(mode.title)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(mode.color)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(mode.color.opacity(0.1), in: Capsule())
        }
    }
}

// MARK: - タイマーバー（モードCのみ）

private struct TimerBar: View {
    let timeRemaining: Double
    let totalTime:     Double

    private var ratio: Double { max(0, timeRemaining / totalTime) }
    private var color: Color {
        if ratio > 0.5 { return DS.gaugeFull }
        if ratio > 0.2 { return .orange }
        return DS.gaugeWarn
    }

    var body: some View {
        HStack(spacing: 8) {
            // 残り秒数（切り上げて表示。0.1秒でも残っていれば "1" と表示する）
            Text(String(format: "%.0f", ceil(timeRemaining)))
                .font(.system(size: 13, weight: .bold, design: .monospaced))
                .foregroundStyle(color)
                .frame(width: 28, alignment: .trailing)

            // バー
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: DS.gaugeRadius)
                        .fill(DS.gaugeBg)
                        .frame(height: 8)
                    RoundedRectangle(cornerRadius: DS.gaugeRadius)
                        .fill(color)
                        .frame(width: max(0, geo.size.width * ratio), height: 8)
                        .animation(.linear(duration: 0.01), value: ratio)
                }
            }
            .frame(height: 8)
        }
    }
}

// MARK: - 数字タイル行

/// 4枚の数字タイルを横一列に並べる。
/// 使用済みのスロットはグレーアウトして再タップを無効にする。
private struct DigitTileRow: View {
    let digits:    [Int]
    let usedSlots: Set<Int>
    let onTap:     (Int) -> Void

    var body: some View {
        HStack(spacing: 10) {
            ForEach(0..<digits.count, id: \.self) { slot in
                DigitTile(
                    value:  digits[slot],
                    isUsed: usedSlots.contains(slot),
                    onTap:  { onTap(slot) }
                )
            }
        }
    }
}

/// 数字タイル1枚。タップすると式に追加され、グレーアウトする。
private struct DigitTile: View {
    let value:  Int
    let isUsed: Bool
    let onTap:  () -> Void

    var body: some View {
        Button(action: onTap) {
            Text("\(value)")
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .foregroundStyle(isUsed ? DS.muted.opacity(0.4) : DS.textPrimary)
                .frame(maxWidth: .infinity)
                .frame(height: 76)
                .background(
                    RoundedRectangle(cornerRadius: DS.btnRadius)
                        .fill(isUsed ? DS.muted.opacity(0.06) : DS.choiceFill)
                        .overlay(
                            RoundedRectangle(cornerRadius: DS.btnRadius)
                                .stroke(
                                    isUsed ? DS.muted.opacity(0.1) : DS.muted.opacity(0.18),
                                    lineWidth: 1.5
                                )
                        )
                )
        }
        .buttonStyle(.plain)
        .disabled(isUsed)
        .animation(.easeInOut(duration: 0.15), value: isUsed)
    }
}

// MARK: - 式の表示エリア

/// ユーザーが組み立て中の式をトークンの横並びで表示する。
/// 正解・不正解・ヒントに応じてフィードバックを表示する。
private struct ExpressionDisplay: View {
    let tokens:    [ExprToken]
    let judgment:  TenPuzzleJudgment?
    let state:     TenPuzzleProblemState
    let shownHint: String?

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: DS.tagRadius)
                .fill(bgColor)
                .overlay(
                    RoundedRectangle(cornerRadius: DS.tagRadius)
                        .stroke(borderColor, lineWidth: 1.5)
                )

            // ヒント / フィードバック / 式 / プレースホルダー を優先順に表示する
            Group {
                if let hint = shownHint {
                    // ヒント・宣言不正解のとき：解の例を表示する
                    VStack(spacing: 4) {
                        Text("こたえ例")
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundStyle(DS.muted)
                        Text(hint)
                            .font(.system(size: 18, weight: .bold, design: .monospaced))
                            .foregroundStyle(DS.textPrimary)
                    }

                } else if state == .correct || state == .wrong {
                    // 正解・不正解フィードバック
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
                    // 式が空のとき：プレースホルダー
                    Text("数字タイルをタップして式を作ろう")
                        .font(.system(size: 13, weight: .regular, design: .rounded))
                        .foregroundStyle(DS.muted.opacity(0.6))

                } else {
                    // 式トークンを横に並べて表示（スクロール可能）
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 4) {
                            ForEach(tokens) { token in
                                TokenChip(token: token)
                            }
                            CursorView()
                        }
                        .padding(.horizontal, 12)
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
}

/// 式の1トークンをチップ（角丸矩形）で表示する
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

/// 式の末尾に表示するカーソル（点滅するバー）
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

/// 演算子（+−×÷）・括弧・削除・リセットのボタンを2行に並べたキーボード。
private struct OperatorKeyboard: View {
    let onOp:    (String) -> Void
    let onParen: (String) -> Void
    let onDelete: () -> Void
    let onReset:  () -> Void
    let disabled: Bool

    private let row1 = ["+", "−", "×", "÷"]

    var body: some View {
        VStack(spacing: 8) {
            // 演算子行
            HStack(spacing: 8) {
                ForEach(row1, id: \.self) { op in
                    KeyboardButton(label: op, color: DS.primary.opacity(0.8)) {
                        onOp(op)
                    }
                }
            }

            // 括弧・削除行
            HStack(spacing: 8) {
                KeyboardButton(label: "(", color: DS.muted.opacity(0.6)) { onParen("(") }
                KeyboardButton(label: ")", color: DS.muted.opacity(0.6)) { onParen(")") }

                // 削除ボタン（⌫）
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

                // リセットボタン
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

/// キーボードの1ボタン（演算子・括弧）
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

/// 「こたえる」ボタン + モードB（ヒント/スキップ）またはモードC（作れない！）のボタン
private struct SubmitArea: View {
    var viewModel: TenPuzzleViewModel

    private var canSubmit: Bool {
        viewModel.problemState == .solving && !viewModel.tokens.isEmpty
    }

    var body: some View {
        VStack(spacing: 10) {
            // こたえる（提出）ボタン
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

            // モード別のサブボタン
            switch viewModel.selectedMode {

            case .modeB:
                HStack(spacing: 10) {
                    SubActionButton(
                        label:    "ヒントを見る",
                        icon:     "lightbulb",
                        color:    .orange,
                        action:   { viewModel.useHint() },
                        disabled: viewModel.problemState != .solving
                                  || viewModel.currentProblem?.example == nil
                    )
                    SubActionButton(
                        label:    "スキップ",
                        icon:     "forward",
                        color:    DS.muted,
                        action:   { viewModel.skipProblem() },
                        disabled: viewModel.problemState != .solving
                    )
                }

            case .modeC:
                Button {
                    viewModel.declareImpossible()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "xmark.circle")
                            .font(.system(size: 15, weight: .semibold))
                        Text("作れない！と宣言する")
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                    }
                    .foregroundStyle(DS.gaugeWarn)
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .background(DS.gaugeWarn.opacity(0.10), in: RoundedRectangle(cornerRadius: DS.tagRadius))
                }
                .buttonStyle(.plain)
                .disabled(viewModel.problemState != .solving)

            case .modeA:
                EmptyView()
            }
        }
    }
}

/// サブアクションの小さいボタン（ヒント / スキップ）
private struct SubActionButton: View {
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
            .frame(height: 40)
            .background(color.opacity(0.10), in: RoundedRectangle(cornerRadius: DS.tagRadius))
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.4 : 1.0)
    }
}

// MARK: - TenPuzzleResultView（結果画面）

/// セッション（10問）終了後の結果画面。
/// 正解数・モード別の詳細・もう一度/ホームボタンを表示する。
private struct TenPuzzleResultView: View {

    var viewModel: TenPuzzleViewModel

    private var record: TenPuzzleSessionRecord { viewModel.record }
    private var mode:   TenPuzzleMode           { viewModel.selectedMode }

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            // スコアカード
            VStack(spacing: 20) {
                // 大きなスコア表示
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

                // モード別の詳細
                VStack(spacing: 8) {
                    switch mode {
                    case .modeB:
                        ResultRow(label: "ヒントなしで正解", value: "\(record.selfSolved)問")
                        ResultRow(label: "ヒントで正解",     value: "\(record.hintUsed)問")
                        ResultRow(label: "スキップ",         value: "\(record.skipped)問")
                    case .modeC:
                        ResultRow(label: "自力で正解",           value: "\(record.correct - record.impossible)問")
                        ResultRow(label: "「作れない！」で正解", value: "\(record.impossible)問")
                    case .modeA:
                        EmptyView()
                    }
                }
                .padding(.horizontal, 8)
            }
            .padding(28)
            .background(DS.cardShadow())

            Spacer()

            // アクションボタン
            VStack(spacing: 12) {
                // もう一度（同じモードで再挑戦）
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

                // ホームに戻る（モード選択へ）
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

    /// 正解率に応じたリザルト絵文字
    private var resultEmoji: String {
        // record.total は常に10以上なので除算は安全
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

/// 結果詳細の1行（ラベル + 値）
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
