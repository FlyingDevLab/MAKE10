//
//  JankenView.swift
//  FDL-TenBlitz
//
//  Created by 空飛ぶ研究室(FlyingDevLab) on 2026/06/03.
//

// 指令じゃんけんのUI全体を担うファイル。
// JankenViewがルートとなり、ViewModel.phaseに応じて以下の画面を切り替える。
//   idle             → JankenTitleView（難易度選択）
//   countdown        → JankenCountdownView（3→2→1カウントダウン）
//   phaseTransition  → JankenPhaseTransitionView（挑戦モードのフェーズ切替テロップ）
//   playing          → JankenPlayingView（メインゲーム）
//   finished         → JankenResultView（リザルト画面・別ファイル）
//
// SharedFrameのバックボタン・画面離脱でstopGame()が呼ばれる。

import SwiftUI

// MARK: - JankenView（ルート）

struct JankenView: View {

    @State private var viewModel = JankenViewModel()

    var body: some View {
        ZStack {
            switch viewModel.phase {
            case .idle:
                JankenTitleView(viewModel: viewModel)
                    .transition(.opacity)
            case .countdown(let n):
                JankenCountdownView(count: n)
                    .transition(.opacity)
            case .phaseTransition(let key):
                JankenPhaseTransitionView(telopKey: key)
                    .transition(.opacity)
            case .playing:
                JankenPlayingView(viewModel: viewModel)
                    .transition(.opacity)
            case .finished:
                JankenResultView(viewModel: viewModel)
                    .transition(.opacity)
            }
        }
        // ← duration 変更可
        .animation(.easeInOut(duration: 0.3), value: viewModel.phase)
        .onDisappear { viewModel.stopGame() }
    }
}

// MARK: - JankenTitleView（難易度選択）

private struct JankenTitleView: View {

    var viewModel: JankenViewModel

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            // ── 遊び方カード ──────────────────────────────────
            VStack(alignment: .leading, spacing: 12) {
                Label("janken_how_to_play_title", systemImage: "questionmark.circle.fill")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(DS.muted)

                HStack(alignment: .top, spacing: 8) {
                    Text("✊").font(.system(size: 18))
                    Text("janken_how_to_play_body")
                        .font(.system(size: 15, weight: .medium, design: .rounded))
                        .foregroundStyle(DS.textPrimary)
                }
                HStack(alignment: .top, spacing: 8) {
                    Text("⏱️").font(.system(size: 18))
                    Text("janken_how_to_play_penalty")
                        .font(.system(size: 15, weight: .medium, design: .rounded))
                        .foregroundStyle(DS.textPrimary)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(DS.card, in: RoundedRectangle(cornerRadius: DS.sectionRadius))
            .padding(.horizontal, 24)

            Spacer()

            // ── 難易度ボタン ──────────────────────────────────
            VStack(spacing: 12) {
                difficultyButton(.easy,      color: DS.gaugeFull)
                difficultyButton(.hard,      color: DS.blitzColor)
                difficultyButton(.challenge, color: DS.accent)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 32)
        }
    }

    /// 難易度ボタン1つ。タイトル・手数・ベストタイムを表示する。
    private func difficultyButton(
        _ difficulty: JankenDifficulty,
        color: Color
    ) -> some View {
        Button {
            SoundManager.shared.vibrate()
            SoundManager.shared.playTap()
            withAnimation { viewModel.start(difficulty: difficulty) }
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(difficulty.labelKey)
                        .font(.system(size: 22, weight: .black, design: .rounded))
                        .foregroundStyle(.white)

                    // ベストタイムがあれば表示
                    if let best = bestTimeText(for: difficulty) {
                        Text("🏆 \(best)")
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundStyle(.white.opacity(0.85))
                    }
                }

                Spacer()

                // 手数ヒント
                Text("\(difficulty.totalRounds)手")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.75))
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 18)
            .background(
                RoundedRectangle(cornerRadius: DS.btnRadius)
                    .fill(color)
                    .shadow(color: color.opacity(0.35), radius: 8, x: 0, y: 4)
            )
        }
        .buttonStyle(.plain)
    }

    /// UserDefaultsからベストタイムを読み取って表示文字列を返す
    private func bestTimeText(for difficulty: JankenDifficulty) -> String? {
        let v = UserDefaults.standard.double(forKey: difficulty.bestTimeKey)
        guard v > 0 else { return nil }
        let m  = Int(v) / 60
        let s  = Int(v) % 60
        let cs = Int((v - Double(Int(v))) * 100)
        return String(format: "%02d:%02d.%02d", m, s, cs)
    }
}

// MARK: - JankenCountdownView（カウントダウン）

private struct JankenCountdownView: View {

    let count: Int

    @State private var scale:   CGFloat = 0.4
    @State private var opacity: Double  = 0.0

    var body: some View {
        ZStack {
            DS.bg.ignoresSafeArea()

            if count > 0 {
                Text("\(count)")
                    .font(.system(size: 120, weight: .black, design: .rounded))  // ← 変更可
                    .foregroundStyle(DS.primary)
                    .scaleEffect(scale)
                    .opacity(opacity)
                    .id(count)  // countが変わるたびに別Viewとして扱いアニメをリセット
                    .onAppear {
                        scale   = 0.4
                        opacity = 0.0
                        withAnimation(.spring(duration: 0.3, bounce: 0.4)) {
                            scale   = 1.0
                            opacity = 1.0
                        }
                    }
            }
        }
    }
}

// MARK: - JankenPhaseTransitionView（フェーズ切替テロップ・挑戦モードのみ）

private struct JankenPhaseTransitionView: View {

    let telopKey: String

    @State private var scale:   CGFloat = 0.6
    @State private var opacity: Double  = 0.0

    var body: some View {
        ZStack {
            DS.bg.ignoresSafeArea()

            Text(LocalizedStringKey(telopKey))
                .font(.system(size: 38, weight: .black, design: .rounded))  // ← 変更可
                .foregroundStyle(DS.primary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
                .scaleEffect(scale)
                .opacity(opacity)
                .onAppear {
                    withAnimation(.spring(duration: 0.4, bounce: 0.3)) {
                        scale   = 1.0
                        opacity = 1.0
                    }
                }
        }
    }
}

// MARK: - Hand Button State

/// じゃんけんボタンの表示状態。QuizChoiceButtonStateと同じ設計思想で実装している。
/// normal：回答前 / correct：正解で選んだ手 / wrong：不正解で選んだ手
private enum JankenHandButtonState: Equatable { case normal, correct, wrong }

// MARK: - JankenHandButton

/// じゃんけんの手（✊✌️🖐️）を表示するボタン。
/// クイズの QuizChoiceButton と同じ視覚スタイルを踏襲する：
///   - 背景：薄い色（opacity 0.15）
///   - 枠線：DS.gaugeFull（正解）/ DS.gaugeWarn（不正解）のカラーボーダー
///   - アイコン：右上に checkmark / xmark
///   - スケール：正解時のみ 1.03 に拡大
private struct JankenHandButton: View {
    let hand:   JankenHand
    let state:  JankenHandButtonState
    let action: () -> Void

    // stateに応じた背景色。クイズと同じ opacity(0.15) の薄い色を使う
    private var bgColor: Color {
        switch state {
        case .normal:  return DS.choiceFill
        case .correct: return DS.gaugeFull.opacity(0.15)
        case .wrong:   return DS.gaugeWarn.opacity(0.15)
        }
    }

    // stateに応じた枠線色。正解・不正解のみ色付き枠線を表示する
    private var borderColor: Color {
        switch state {
        case .normal:  return DS.muted.opacity(0.15)
        case .correct: return DS.gaugeFull
        case .wrong:   return DS.gaugeWarn
        }
    }

    var body: some View {
        Button(action: action) {
            ZStack {
                // ── 背景 + 枠線 ──────────────────────────────
                RoundedRectangle(cornerRadius: DS.cardRadius)
                    .fill(bgColor)
                    .overlay(
                        RoundedRectangle(cornerRadius: DS.cardRadius)
                            .stroke(borderColor, lineWidth: 1.8)
                    )
                    // 回答前のみシャドウを表示してタップ可能感を演出する
                    .shadow(
                        color: .black.opacity(state == .normal ? 0.06 : 0),
                        radius: 5, x: 0, y: 2
                    )

                // ── 絵文字 ──────────────────────────────────
                Text(hand.emoji)
                    .font(.system(size: 52))   // ← 変更可
                    .padding(.vertical, 16)    // ← 変更可

                // ── 正解アイコン（右上） ──────────────────────
                if state == .correct {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(DS.gaugeFull)
                        .font(.system(size: 18, weight: .bold))
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                        .padding(8)
                }

                // ── 不正解アイコン（右上） ────────────────────
                if state == .wrong {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(DS.gaugeWarn)
                        .font(.system(size: 18, weight: .bold))
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                        .padding(8)
                }
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        // 正解ボタンのみわずかに拡大して正解を視覚的に強調する（クイズと同じ 1.03）
        .scaleEffect(state == .correct ? 1.03 : 1.0)  // ← 変更可
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: state)
    }
}

// MARK: - JankenPlayingView（メインゲーム画面）

private struct JankenPlayingView: View {

    var viewModel: JankenViewModel

    // ミス時の「+5秒」テキスト表示フラグ
    @State private var showPenaltyText = false

    private var instructionColor: Color {
        viewModel.currentInstruction == .win ? DS.primary : DS.blitzColor
    }

    var body: some View {
        ZStack {

            // ── 背景 ──────────────────────────────────────────
            DS.bg.ignoresSafeArea()

            // ── メインコンテンツ ──────────────────────────────
            VStack(spacing: 0) {

                // ── プログレスバー ────────────────────────────
                VStack(spacing: 4) {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: DS.gaugeRadius)
                                .fill(DS.gaugeBg)
                            RoundedRectangle(cornerRadius: DS.gaugeRadius)
                                .fill(DS.primary)
                                .frame(width: geo.size.width * viewModel.progress)
                                .animation(.easeOut(duration: 0.2), value: viewModel.progress)
                        }
                    }
                    .frame(height: 10)

                    Text("\(viewModel.currentRound) / \(viewModel.totalRounds)")
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(DS.muted)
                }
                .padding(.horizontal, 24)
                .padding(.top, 16)
                .padding(.bottom, 12)

                // ── 挑戦モード：現在フェーズ表示 ─────────────
                // かんたん・むずかしいは非表示。挑戦モードのみ常時表示する。
                if let phaseKey = viewModel.challengePhaseKey {
                    Text(phaseKey)
                        .font(.system(size: 26, weight: .black, design: .rounded))  // ← 変更可
                        .foregroundStyle(instructionColor)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 8)
                        .background(
                            instructionColor.opacity(0.12),
                            in: RoundedRectangle(cornerRadius: DS.sectionRadius)
                        )
                        .padding(.bottom, 8)
                }

                Spacer()

                // ── CPUの手（絵文字・大） ─────────────────────
                Text(viewModel.cpuHand.emoji)
                    .font(.system(size: 96))    // ← 変更可
                    .padding(.bottom, 8)

                // ── 指示テキスト（勝て！/ 負けろ！）───────────
                Text(viewModel.currentInstruction == .win
                     ? LocalizedStringKey("janken_instruction_win")
                     : LocalizedStringKey("janken_instruction_lose"))
                    .font(.system(size: 44, weight: .black, design: .rounded))  // ← 変更可
                    .foregroundStyle(instructionColor)
                    .padding(.bottom, 4)

                Spacer()

                // ── プレイヤーの手ボタン（3択）────────────────
                // クイズの QuizChoiceButton と同じ視覚スタイルを使う
                HStack(spacing: 12) {
                    ForEach(JankenHand.allCases, id: \.self) { hand in
                        JankenHandButton(
                            hand:   hand,
                            state:  handButtonState(for: hand)
                        ) {
                            viewModel.tap(hand)
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 16)

                // ── タイマー ──────────────────────────────────
                Text(viewModel.elapsedFormatted)
                    .font(.system(size: 32, weight: .black, design: .rounded))  // ← 変更可
                    .foregroundStyle(DS.textPrimary)
                    .monospacedDigit()
                    .padding(.bottom, 28)
            }

            // ── 正解/不正解フラッシュオーバーレイ ─────────────
            if let color = viewModel.flashColor {
                color
                    .opacity(0.35)                    // ← 変更可
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
                    .transition(.opacity)
            }

            // ── ミス時の「+5秒」テキスト ─────────────────────
            if showPenaltyText {
                Text("+5秒")
                    .font(.system(size: 52, weight: .black, design: .rounded))  // ← 変更可
                    .foregroundStyle(DS.blitzColor)
                    .allowsHitTesting(false)
                    .transition(.scale(scale: 0.6).combined(with: .opacity))
            }
        }
        .animation(.easeOut(duration: 0.15), value: viewModel.flash)
        .animation(.spring(duration: 0.25, bounce: 0.3), value: showPenaltyText)
        .onChange(of: viewModel.flash) { _, newFlash in
            // 不正解フラッシュのときだけ「+5秒」を短時間表示する
            guard newFlash == .wrong else { return }
            showPenaltyText = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {  // ← 変更可
                showPenaltyText = false
            }
        }
    }

    // MARK: - Helpers

    /// タップされた手のボタン状態を返す。
    /// tappedHand と一致するボタンだけ correct / wrong になり、他は normal のまま。
    private func handButtonState(for hand: JankenHand) -> JankenHandButtonState {
        guard viewModel.tappedHand == hand else { return .normal }
        switch viewModel.flash {
        case .correct: return .correct
        case .wrong:   return .wrong
        case nil:      return .normal  // フラッシュ終了の瞬間は normal に戻す
        }
    }
}
