//
//  WhackAMoleView.swift
//  FDL-TenBlitz
//
//  Created by 空飛ぶ研究室(FlyingDevLab) on 2026/04/13.
//

// index.html の3画面（トップ／ゲーム／リザルト）を SwiftUI で再現。
// MakeTenContentView の SharedFrame 内のコンテンツとして表示される。
// SharedFrame のバックボタンが押されると onDisappear → stopGame() が呼ばれる。
//
// 主な調整ポイント:
//   モグラの外観  → MoleHoleView 内の各パーツ
//   穴の外観      → MoleHoleView の地面・楕円
//   モグラの位置  → moleOffsetY()

import SwiftUI

// MARK: - WhackAMoleView（ルートView・画面切り替え）

struct WhackAMoleView: View {

    @State private var viewModel = WhackAMoleViewModel()

    var body: some View {
        Group {
            switch viewModel.gameState {
            case .title:    WAMTitleView(viewModel: viewModel)
            case .playing:  WAMPlayingView(viewModel: viewModel)
            case .finished: WAMResultView(viewModel: viewModel)
            }
        }
        .transition(.opacity)
        // 画面切り替えトランジション時間 ← 変更可
        .animation(.easeInOut(duration: 0.3), value: viewModel.gameState)
        // SharedFrame の戻るボタン・画面離脱でゲームを止める
        .onDisappear { viewModel.stopGame() }
    }
}

// MARK: - WAMTitleView（タイトル画面）

private struct WAMTitleView: View {
    var viewModel: WhackAMoleViewModel

    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            // ── 遊び方カード ──────────────────────────────────
            // 説明文を変えたいときはここを編集する
            VStack(alignment: .leading, spacing: 12) {
                Label("How to Play", systemImage: "questionmark.circle.fill")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(DS.muted)

                HStack(alignment: .top, spacing: 8) {
                    Text("⏱️").font(.system(size: 18))
                    Text("Hit as many moles as you can in 30 seconds!")
                        .font(.system(size: 15, weight: .medium, design: .rounded))
                        .foregroundStyle(DS.textPrimary)
                }
                HStack(alignment: .top, spacing: 8) {
                    Text("👆").font(.system(size: 18))
                    Text("Tap fast when they pop up!")
                        .font(.system(size: 15, weight: .medium, design: .rounded))
                        .foregroundStyle(DS.textPrimary)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(DS.card, in: RoundedRectangle(cornerRadius: DS.sectionRadius))
            .padding(.horizontal, 24)

            // ── ハイスコア（記録がある場合のみ表示）──────────
            if viewModel.highScore > 0 {
                HStack(spacing: 8) {
                    Text("🏆").font(.system(size: 20))
                    Text("Best Record")
                        .font(.system(size: 16, weight: .medium, design: .rounded))
                        .foregroundStyle(DS.muted)
                    Text("\(viewModel.highScore)")
                        .font(.system(size: 24, weight: .black, design: .rounded))  // ← 数値サイズ
                        .foregroundStyle(DS.accent)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .background(DS.card, in: RoundedRectangle(cornerRadius: DS.sectionRadius))
            }

            Spacer()

            // ── スタートボタン ────────────────────────────────
            Button {
                SoundManager.shared.vibrate()
                SoundManager.shared.playTap()
                withAnimation { viewModel.startGame() }
            } label: {
                Text("Start Game")
                    .font(.system(size: 26, weight: .black, design: .rounded))  // ← ボタン文字サイズ
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)                                      // ← ボタン縦パディング
                    .background(
                        RoundedRectangle(cornerRadius: DS.btnRadius)
                            .fill(DS.primary)
                            .shadow(color: DS.primary.opacity(0.35), radius: 8, x: 0, y: 4)
                    )
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
    }
}

// MARK: - WAMPlayingView（ゲームプレイ画面）

private struct WAMPlayingView: View {
    var viewModel: WhackAMoleViewModel

    // ← count: 3 で3列。変えるときは holeCount も合わせて変更する
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 3)

    var body: some View {
        VStack(spacing: 0) {

            // ── ステータスバー（スコア・残り時間）────────────
            HStack {

                // スコア（左）
                VStack(spacing: 2) {
                    Text("Score")
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(DS.muted)
                    Text("\(viewModel.score)")
                        .font(.system(size: 36, weight: .black, design: .rounded))  // ← スコア数値サイズ
                        .foregroundStyle(DS.primary)
                        .contentTransition(.numericText())
                        .animation(.spring(duration: 0.2), value: viewModel.score)  // ← スコア増加アニメ速度
                }
                .frame(maxWidth: .infinity)

                // 残り時間（右）
                VStack(spacing: 2) {
                    Text("Remaining")
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(DS.muted)
                    Text("\(viewModel.timeLeft)")
                        .font(.system(size: 36, weight: .black, design: .rounded))  // ← タイマー数値サイズ
                        // 警告しきい値以下になると gaugeWarn 色に変わる（しきい値は WAMConfig.warningThreshold）
                        .foregroundStyle(viewModel.isTimerWarning ? DS.gaugeWarn : DS.textPrimary)
                        .contentTransition(.numericText())
                        .animation(.spring(duration: 0.2), value: viewModel.timeLeft)
                }
                .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)  // ← ステータスバーの上下余白
            .background(DS.card)

            // ── モグラグリッド（3×3）──────────────────────────
            LazyVGrid(columns: columns, spacing: 12) {  // ← spacing でマス間隔を調整
                ForEach(0..<9, id: \.self) { index in
                    MoleHoleView(
                        state:   viewModel.moles[index],
                        onWhack: { viewModel.whackMole(at: index) }
                    )
                    .aspectRatio(1, contentMode: .fit)  // 正方形を維持
                }
            }
            .padding(16)   // ← グリッド外周の余白 ← 変更可
            .background(DS.bg)

            Spacer()
        }
    }
}

// MARK: - WAMResultView（リザルト画面）

private struct WAMResultView: View {
    var viewModel: WhackAMoleViewModel

    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            // ── 新記録バナー（新記録時のみ表示）──────────────
            if viewModel.isNewRecord {
                Text("🎉 New Record!")
                    .font(.system(size: 22, weight: .black, design: .rounded))
                    .foregroundStyle(DS.accent)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: DS.sectionRadius)
                            .fill(DS.accent.opacity(0.12))
                    )
                    .transition(.scale.combined(with: .opacity))
            }

            // ── 今回のスコア ──────────────────────────────────
            VStack(spacing: 4) {
                Text("Your Score")
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .foregroundStyle(DS.muted)
                Text("\(viewModel.score)")
                    .font(.system(size: 72, weight: .black, design: .rounded))  // ← スコア数値サイズ
                    .foregroundStyle(DS.primary)
            }
            .padding(.vertical, 20)
            .frame(maxWidth: .infinity)
            .background(DS.card, in: RoundedRectangle(cornerRadius: DS.sectionRadius))
            .padding(.horizontal, 24)

            // ── ハイスコア ────────────────────────────────────
            HStack(spacing: 8) {
                Text("🏆").font(.system(size: 20))
                Text("Best Record")
                    .font(.system(size: 16, weight: .medium, design: .rounded))
                    .foregroundStyle(DS.muted)
                Text("\(viewModel.highScore)")
                    .font(.system(size: 24, weight: .black, design: .rounded))
                    .foregroundStyle(DS.accent)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .background(DS.card, in: RoundedRectangle(cornerRadius: DS.sectionRadius))

            Spacer()

            // ── ボタン群 ──────────────────────────────────────
            VStack(spacing: 12) {

                // もういちどあそぶ
                Button {
                    SoundManager.shared.vibrate()
                    SoundManager.shared.playTap()
                    withAnimation { viewModel.startGame() }
                } label: {
                    Text("Play Again")
                        .font(.system(size: 22, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 18)
                        .background(
                            RoundedRectangle(cornerRadius: DS.btnRadius)
                                .fill(DS.primary)
                                .shadow(color: DS.primary.opacity(0.35), radius: 8, x: 0, y: 4)
                        )
                }
                .buttonStyle(.plain)

                // タイトルへもどる
                // ※ SharedFrame の screen は変えない。WAMTitleView に戻るだけ。
                // ※ SharedFrame 自体の戻りは SharedFrame のバックボタンが担う。
                Button {
                    SoundManager.shared.vibrate()
                    withAnimation { viewModel.stopGame() }
                    withAnimation(.easeInOut(duration: 0.3)) {
                        viewModel.gameState = .title
                    }
                } label: {
                    Text("Back to Title")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundStyle(DS.muted)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(
                            RoundedRectangle(cornerRadius: DS.btnRadius)
                                .fill(DS.card)
                        )
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
    }
}

// MARK: - MoleHoleView（穴1マス）

/// 穴1つ分の View。モグラが穴から出てくるアニメーションを offset + clipped で実現する。
///
/// 構造（ZStack・下から上の順）:
///   1. 地面（茶色の角丸矩形）
///   2. 穴（暗い楕円）
///   3. モグラ本体 + 叩かれた演出（clipped で穴の上だけ見える）
private struct MoleHoleView: View {
    let state:   MoleState
    let onWhack: () -> Void

    var body: some View {
        GeometryReader { geo in
            // size = セルの一辺のビューpx サイズ（正方形なので width = height）
            let size = geo.size.width

            ZStack(alignment: .bottom) {

                // ── 地面（穴の周りの土）──────────────────────
                // ← cornerRadius: 12 で丸みを調整できる
                // ← opacity(0.25) で土の濃さを調整できる
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(red: 0.55, green: 0.38, blue: 0.20).opacity(0.25))  // ← 土の色・濃さ

                // ── 穴（暗い楕円）────────────────────────────
                // ← size の倍率で穴のサイズを変えられる（幅 0.72 / 高さ 0.28）
                Ellipse()
                    .fill(Color(red: 0.18, green: 0.10, blue: 0.04))  // ← 穴の色
                    .frame(width: size * 0.72, height: size * 0.28)    // ← 穴のサイズ倍率
                    .padding(.bottom, 6)                                // ← 穴の下端余白

                // ── モグラ + 叩き演出（穴の上だけ表示）────────
                // .clipped() で穴より下の部分が見えないようにカットする
                ZStack {
                    // 叩かれた瞬間：⭐ が弾けて消える演出
                    if state.isHit {
                        Text("⭐")
                            .font(.system(size: size * 0.28))      // ← ⭐ サイズ（size の倍率）
                            .offset(y: -size * 0.05)               // ← ⭐ の縦オフセット
                            .transition(.scale(scale: 0.3).combined(with: .opacity))
                    }

                    // モグラ本体（絵文字）
                    // ← 絵文字を変えるとモグラの見た目が変わる
                    Image("mole")
                        .resizable()
                            .scaledToFit()
                            .frame(width: size * 1.52, height: size * 1.52)  // ← サイズは絵文字と同じ倍率
                        .offset(y: moleOffsetY(size: size))         // ← 状態に応じたY位置
                        // isVisible が変わったとき（出現・消滅）のアニメ
                        // ← duration / bounce を変えると飛び出し感が変わる
                        .animation(.spring(duration: 0.25, bounce: 0.3), value: state.isVisible)
                        // isHit が変わったとき（叩かれた瞬間）のアニメ
                        .animation(.spring(duration: 0.12),              value: state.isHit)
                }
                // ← height: size * 0.9 でクリップ高さを調整（大きくするとモグラが多く見える）
                .frame(width: size, height: size * 0.9)
                .clipped()
            }
        }
        // タップ判定領域をセル全体に広げる
        .contentShape(Rectangle())
        .onTapGesture {
            // 出ているモグラのみ叩ける（isVisible = false のときは無視）
            guard state.isVisible else { return }
            onWhack()
        }
    }

    /// モグラの縦オフセットを状態に応じて返す。
    /// オフセットが大きい（正の値）ほどモグラが下に隠れる。
    ///
    ///   isHit    → 叩かれたら即引っ込む（0.55 = ほぼ穴の中）
    ///   isVisible → 穴から顔を出す（0.10 = 少しだけ出ている）
    ///   非表示    → 穴の下に完全に隠れる（0.90 = ほぼ見えない）
    ///
    /// ← 値を変えるとモグラの出っ張り具合が変わる
    private func moleOffsetY(size: CGFloat) -> CGFloat {
        if state.isHit     { return size * 0.55 }  // ← 叩かれた後の引っ込み量
        if state.isVisible { return size * 0.10 }  // ← 出現時の顔の出し量（小さいほど多く見える）
        return size * 0.90                          // ← 非表示時の隠れ量（大きいほど深く隠れる）
    }
}
