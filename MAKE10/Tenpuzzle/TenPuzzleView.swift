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
        .onAppear    { viewModel.resume(); playScreenshotScene() }
        .onDisappear { viewModel.suspend() }
        .onReceive(NotificationCenter.default.publisher(
            for: UIApplication.didEnterBackgroundNotification)
        ) { _ in viewModel.suspend() }
        .onReceive(NotificationCenter.default.publisher(
            for: UIApplication.willEnterForegroundNotification)
        ) { _ in viewModel.resume() }
    }
}

extension TenPuzzleView {

    /// 撮影モード（ScreenshotMode.swift を参照）: 「むずかしい」を始め、解の例どおりに式を組み立てておく。
    /// 「=」は押さないので、組み立てた式と「= 10」が見えたままになる。
    fileprivate func playScreenshotScene() {
        guard ScreenshotMode.scene == .tenPuzzle else { return }
        viewModel.startSession(mode: .modeB)
        // ＋だけの式より、いろいろな記号を使う問題のほうが見ばえがよいので、×と−を使う問題に差しかえる
        if let p = TenPuzzleDatabase.solvablePool.shuffled().first(where: {
            guard let ex = $0.example else { return false }
            return ex.contains("×") && ex.contains("−")
        }) {
            viewModel.currentProblem = p
        }
        guard let problem = viewModel.currentProblem, let example = problem.example else { return }
        var used: Set<Int> = []
        for (i, ch) in example.enumerated() {
            ScreenshotMode.after(1.0 + Double(i) * 0.15) {
                if let digit = ch.wholeNumberValue {
                    // 同じ数字が2枚あるときは、まだ使っていない方を使う
                    if let slot = problem.digits.indices.first(where: { problem.digits[$0] == digit && !used.contains($0) }) {
                        used.insert(slot)
                        viewModel.tapDigit(slot: slot)
                    }
                } else if ch == "(" || ch == ")" {
                    viewModel.tapParen(String(ch))
                } else {
                    viewModel.tapOperator(String(ch))
                }
            }
        }
    }
}

// MARK: - TenPuzzleHomeView（モード選択）

private struct TenPuzzleHomeView: View {

    var viewModel: TenPuzzleViewModel

    // ★ ScrollView で包んでいる理由 ★
    //   ルールの説明を足したので、横向きや小さい画面では縦に収まらないことがある。
    //   収まるときは minHeight で画面いっぱいに広げて中央に置き、揺れもしない（basedOnSize）。
    var body: some View {
        GeometryReader { geo in
            ScrollView {
                VStack(spacing: 0) {
                    Spacer(minLength: 16)

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
                    .wallpaperCushion()   // かべがみの上でも読めるように（DesignSystem.swift を参照）
                    .padding(.bottom, 28)

                    VStack(spacing: 14) {
                        ForEach(TenPuzzleMode.allCases, id: \.rawValue) { mode in
                            ModeCard(
                                mode:       mode,
                                bestStreak: viewModel.bestStreak(for: mode),
                                bestTime:   viewModel.bestTime(for: mode)
                            ) {
                                SoundManager.shared.vibrate()
                                SoundManager.shared.playTap()
                                viewModel.startSession(mode: mode)
                            }
                        }
                    }
                    .padding(.horizontal, 24)

                    TenPuzzleRuleList()
                        .padding(.horizontal, 28)
                        .padding(.top, 18)

                    Spacer(minLength: 16)
                }
                .frame(maxWidth: .infinity, minHeight: geo.size.height)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
    }
}

/// スコアと出題数の決まり。遊び始める前に一度目に入るよう、モードの下に小さく置く。
private struct TenPuzzleRuleList: View {
    private let rules: [LocalizedStringKey] = [
        "スコアは、ヒントを使わずに続けて正解した数。ヒントを使うとそこで止まる。",
        "10問はかならず遊べる。ヒントを使っていなければ、20問目まで続く。",
        "20問ぜんぶヒントなしで正解するとクリア。記録はクリアタイムにかわる。",
        "チャレンジで「作れない！」を外すと、クリアタイムに1分たされる。",
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(rules.indices, id: \.self) { i in
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(verbatim: "・")
                    Text(rules[i])
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .font(.system(size: 12, weight: .regular, design: .rounded))
        .foregroundStyle(DS.muted)
        .frame(maxWidth: .infinity, alignment: .leading)
        .wallpaperCushion()
    }
}

private struct ModeCard: View {
    let mode:       TenPuzzleMode
    let bestStreak: Int
    let bestTime:   TimeInterval?
    let onTap:      () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 16) {
                Text(mode.icon)
                    .font(.system(size: 28))

                VStack(alignment: .leading, spacing: 4) {
                    // ベスト記録はモード名の横に置く（右端に置くと説明文の幅が狭くなって折り返しが増えるため）
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(mode.title)
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                            .foregroundStyle(DS.textPrimary)
                        bestRecord
                    }
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
                    .tintFill(mode.color.opacity(0.08))
                    .overlay(
                        RoundedRectangle(cornerRadius: DS.tagRadius)
                            .stroke(mode.color.opacity(0.25), lineWidth: 1.5)
                    )
            )
        }
        .buttonStyle(.plain)
    }

    /// ベスト記録。クリア済みのモードは「★ 連続正解」から「🏆 クリアタイム」に変わる
    /// （満点は誰でも同じ点なので、数字を出しても差が見えないため）。
    /// 記録がないときは何も出さない（初回プレイで 0 が並ぶのを避ける）。
    @ViewBuilder
    private var bestRecord: some View {
        if let bestTime {
            Text(verbatim: "🏆 \(TenPuzzleViewModel.formatTime(bestTime))")
                .font(.system(size: 13, weight: .heavy, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(DS.gaugeFull)
        } else if bestStreak > 0 {
            Text(verbatim: "★ \(bestStreak)")
                .font(.system(size: 13, weight: .heavy, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(mode.color)
        }
    }
}

// MARK: - TenPuzzleGameView（メインゲーム）

private struct TenPuzzleGameView: View {

    var viewModel: TenPuzzleViewModel

    var body: some View {
        VStack(spacing: 0) {
            // 問題カウンター
            ProblemCounter(
                current:      viewModel.problemNumber,
                total:        viewModel.problemTotal,
                score:        viewModel.score,
                scoreStopped: !viewModel.streakActive,
                mode:         viewModel.selectedMode
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
            if let content = viewModel.hintBannerContent {
                HintBanner(content: content,
                           stoppedScore: viewModel.hintStoppedScore ? viewModel.score : nil)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 8)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            // 式の表示エリア
            ExpressionDisplay(
                tokens:    viewModel.tokens,
                judgment:  viewModel.lastJudgment,
                state:     viewModel.problemState,
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

/// 「n / 総数」と、スコア・モード名。
/// 総数は「この先いくつ遊べるか」（TenPuzzleViewModel.problemTotal を参照）なので、ヒントを使うと変わる。
private struct ProblemCounter: View {
    let current:      Int
    let total:        Int
    let score:        Int
    let scoreStopped: Bool
    let mode:         TenPuzzleMode

    var body: some View {
        HStack(spacing: 12) {
            HStack(spacing: 2) {
                Text(verbatim: "\(current)")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(mode.color)
                Text(verbatim: "/ \(total)")
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(DS.muted)
            }
            .monospacedDigit()
            .wallpaperCushion()

            Spacer()

            // ヒントで止まったスコアは色を落とすだけにする。
            // 打ち消し線だと「取り消された」と読めてしまうため。
            HStack(spacing: 4) {
                Text("SCORE")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(DS.muted)
                Text(verbatim: "\(score)")
                    .font(.system(size: 18, weight: .black, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(scoreStopped ? DS.muted : DS.textPrimary)
            }
            .wallpaperCushion()

            Text(mode.title)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(mode.color)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Capsule().tintFill(mode.color.opacity(0.1)))
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
/// このヒントでスコアが止まったときは、2行目に「スコアは N で止まります」も出す。
private struct HintBanner: View {
    let content: TenPuzzleViewModel.HintBannerContent
    /// このヒントで止まったスコア（止まったのが前の問題なら nil）
    let stoppedScore: Int?

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "lightbulb.fill")
                .foregroundStyle(.orange)
                .font(.system(size: 15))

            VStack(alignment: .leading, spacing: 2) {
                // ★ 解の例（数式）は翻訳不要なので Text(String) のまま、
                //   「作れません」は翻訳が必要なので LocalizedStringKey で渡す。
                //   （設計の理由は TenPuzzleViewModel.HintBannerContent のコメント参照）
                switch content {
                case .example(let expr):
                    Text(expr)
                        .font(.system(size: 15, weight: .bold, design: .monospaced))
                        .foregroundStyle(DS.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                case .impossibleMessage:
                    Text("この問題は10を作れません")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(DS.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }

                if let stoppedScore {
                    Text("スコアは \(stoppedScore) で止まります")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(DS.muted)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
            }

            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: DS.tagRadius)
                .tintFill(Color.orange.opacity(0.10))
                .overlay(
                    RoundedRectangle(cornerRadius: DS.tagRadius)
                        .stroke(Color.orange.opacity(0.3), lineWidth: 1.2)
                )
        )
    }
}

// MARK: - 式の表示エリア

/// 状態に応じて表示を切り替える：
///   .correct / .wrong  → 正解・不正解フィードバック（「作れない！」の外れもここ）
///   tokens が空         → プレースホルダー
///   tokens あり         → トークン + 途中計算値（liveValue）
/// 不正解のあとも式は消さないので、フィードバックが終わると組み立てた式に戻る。
private struct ExpressionDisplay: View {
    let tokens:    [ExprToken]
    let judgment:  TenPuzzleJudgment?
    let state:     TenPuzzleProblemState
    let liveValue: Double?

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: DS.tagRadius)
                .tintFill(bgColor)   // かべがみの上でも透けない（DesignSystem の tintFill）
                .overlay(
                    RoundedRectangle(cornerRadius: DS.tagRadius)
                        .stroke(borderColor, lineWidth: 1.5)
                )

            Group {
                if state == .correct || state == .wrong {
                    HStack(spacing: 8) {
                        Text(state == .correct ? "⭕️" : "❌")
                            .font(.system(size: 28))
                        if let j = judgment {
                            Text(j.message)
                                .font(.system(size: 16, weight: .bold, design: .rounded))
                                .foregroundStyle(j.color)
                                .lineLimit(2)
                                .minimumScaleFactor(0.7)
                        }
                    }
                    .padding(.horizontal, 12)

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
                            if val.isFinite {
                                // 割り切れないときは 1/3 のように分数で出す（TenPuzzleValidator.formatValue を参照）
                                Text(verbatim: "= \(TenPuzzleValidator.formatValue(val))")
                                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                                    .foregroundStyle(
                                        abs(val - 10) < 1e-9 ? DS.gaugeFull : DS.muted.opacity(0.7)
                                    )
                                    .padding(.trailing, 12)
                                    .lineLimit(1)
                            } else {
                                // 0 で割ると無限大か NaN になる
                                Text("0では割れないよ")
                                    .font(.system(size: 12, weight: .bold, design: .rounded))
                                    .foregroundStyle(DS.gaugeWarn)
                                    .padding(.trailing, 12)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.7)
                            }
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
        case .correct: return DS.gaugeFull.opacity(0.08)
        case .wrong:   return DS.gaugeWarn.opacity(0.08)
        default:       return DS.choiceFill
        }
    }

    private var borderColor: Color {
        switch state {
        case .correct: return DS.gaugeFull.opacity(0.4)
        case .wrong:   return DS.gaugeWarn.opacity(0.4)
        default:       return DS.muted.opacity(0.15)
        }
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
            .background(RoundedRectangle(cornerRadius: 6).tintFill(bg))
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
                        .background(RoundedRectangle(cornerRadius: DS.tagRadius).tintFill(DS.muted.opacity(0.10)))
                }
                .buttonStyle(.plain)
                .disabled(disabled)

                Button(action: onReset) {
                    Text("リセット")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(DS.gaugeWarn.opacity(0.85))
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(RoundedRectangle(cornerRadius: DS.tagRadius).tintFill(DS.gaugeWarn.opacity(0.08)))
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
                .background(RoundedRectangle(cornerRadius: DS.tagRadius).tintFill(color.opacity(0.10)))
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
                            .tintFill(canSubmit ? DS.primary : DS.muted.opacity(0.3))
                    )
            }
            .buttonStyle(.plain)
            .disabled(!canSubmit)
            // ★ ボタンの外側にも背景色を敷く理由 ★
            //   押せないとき（.disabled）は、ボタン全体が中の塗りごと薄く表示される。
            //   そのため tintFill で敷いた背景色まで薄くなり、かべがみが透けて文字が読めなくなる。
            //   ボタンの外側に同じ形で敷いておけば、薄くならないので透けない（かべがみを使わないときは何も敷かない）。
            .background(RoundedRectangle(cornerRadius: DS.btnRadius).tintFill(.clear))
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

                // 「作れない！」ボタン（チャレンジのみ）
                if viewModel.selectedMode.allowsImpossible {
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
    let label:    LocalizedStringKey
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
            .background(RoundedRectangle(cornerRadius: DS.tagRadius).tintFill(color.opacity(disabled ? 0.05 : 0.10)))
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

                    // クリア（満点）はタイム勝負にする。満点は誰でも同じ点なので、
                    // 連続正解の数字を出しても人による差が見えないため。
                    Group {
                        if record.isCleared { Text("クリアタイム") } else { Text("連続正解") }
                    }
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(DS.muted)
                    Text(verbatim: record.clearTime.map(TenPuzzleViewModel.formatTime) ?? "\(record.score)")
                        .font(.system(size: 52, weight: .black, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(mode.color)

                    bestLine
                        .padding(.top, 2)

                    if record.isCleared {
                        Text("クリア！")
                            .font(.system(size: 20, weight: .black, design: .rounded))
                            .foregroundStyle(DS.accent)
                            .padding(.top, 4)
                    }
                }

                VStack(spacing: 8) {
                    ResultRow(label: "あそんだ問題", value: "\(record.questionCount)問")
                    if mode.allowsImpossible {
                        ResultRow(label: "「作れない！」で正解", value: "\(record.impossible)問")
                    }
                    if record.hintUsed > 0 {
                        ResultRow(label: "ヒントを使用", value: "\(record.hintUsed)問")
                    }
                    if record.penalty > 0 {
                        ResultRow(label: "タイムにたされた時間",
                                  verbatim: "+\(TenPuzzleViewModel.formatTime(record.penalty))")
                    }
                }
                .padding(.horizontal, 8)
            }
            .padding(28)
            .background(DS.cardShadow())

            Spacer()

            EnergyRewardBanner()

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
                        .wallpaperCushion()
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 24)
        }
    }

    /// ベスト記録の行。
    ///   クリアした      … 新記録なら「さいこうきろく！」、そうでなければベストタイム
    ///   クリアしていない … そのモードを前にクリアしていればベストタイム
    ///                      （更新すべき記録がもうタイムだけなので）、
    ///                      まだなら連続正解の新記録かベスト
    @ViewBuilder
    private var bestLine: some View {
        let bestTime = viewModel.bestTime(for: mode)
        if record.isNewBest && (record.isCleared || bestTime == nil) {
            Text("tenpuzzle_new_best")
                .font(.system(size: 18, weight: .black, design: .rounded))
                .foregroundStyle(DS.gold)
        } else if let bestTime {
            bestLabel(value: "🏆 \(TenPuzzleViewModel.formatTime(bestTime))")
        } else if viewModel.bestStreak(for: mode) > 0 {
            bestLabel(value: "★ \(viewModel.bestStreak(for: mode))")
        }
    }

    private func bestLabel(value: String) -> some View {
        HStack(spacing: 6) {
            Text("tenpuzzle_best_label")
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundStyle(DS.muted)
            Text(verbatim: value)
                .font(.system(size: 17, weight: .black, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(DS.accent)
        }
    }

    private var resultEmoji: String {
        if record.isCleared { return "🏆" }
        switch record.score {
        case 16...: return "🎉"
        case 10...: return "😊"
        case 5...:  return "🙂"
        default:    return "💪"
        }
    }
}

private struct ResultRow: View {
    // ★ label・value ともに LocalizedStringKey にしている理由 ★
    //   Xcode の文字列抽出は Text() に限らず、LocalizedStringKey 型の引数に
    //   渡されたリテラルをすべて拾う。value を String 型のままにすると
    //   保証がなくなるため、label と同じ型に揃えている。
    //   呼び出し側で "\(件数)問" のようにリテラル文字列補間を直接渡せば、
    //   "%lld問" という書式キーとして自動抽出・翻訳される
    //  （janken の "\(difficulty.totalRounds)手" と同じパターン）。
    let label: LocalizedStringKey
    let value: Text

    init(label: LocalizedStringKey, value: LocalizedStringKey) {
        self.label = label
        self.value = Text(value)
    }

    /// 値が「+1:00」のような、どの言語でも同じ文字列のとき（翻訳キーにしない）
    init(label: LocalizedStringKey, verbatim value: String) {
        self.label = label
        self.value = Text(verbatim: value)
    }

    var body: some View {
        HStack {
            Text(label)
                .font(.system(size: 14, weight: .regular, design: .rounded))
                .foregroundStyle(DS.muted)
            Spacer()
            value
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(DS.textPrimary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(DS.choiceFill, in: RoundedRectangle(cornerRadius: 10))
    }
}
