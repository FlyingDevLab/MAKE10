//
//  TitleView.swift
//  FDL-TenBlitz
//
//  Created by 空飛ぶ研究室(FlyingDevLab) on 2026/03/08.
//

// 【このファイルの役割】
// タイトル画面のルートビュー。ゲームモード選択ボタン・ハイスコア表示・
// 「足して10になる」様子をループアニメで見せるデモカードを管理する。
// アニメロジックは runTitleLoop / resetState に分離し、ModeButton は再利用可能な独立コンポーネントとして定義。

import SwiftUI

struct TitleView: View {
    // ゲーム全体の状態管理（ハイスコア・解放フラグ・ゲーム開始などを委譲）
    var viewModel:    GameViewModel
    // クイズモード選択画面を開くコールバック（親ビューが Sheet 等を制御する）
    var onGamePicker: () -> Void

    // 画面外左端のオフセット量。@State初期値はSwiftの制約でリテラル必須のため、
    // resetState() 内ではこの定数を参照して値の一元管理を保つ。
    private let offScreenLeading: CGFloat = -220

    // ─── アニメーション用 State ───────────────────────────────────────

    // デモカード中央に表示する数字（1〜9 のランダム値）
    @State private var centerNumber:    Int     = Int.random(in: 1...9)
    // 左から飛んでくる「足す数」（centerNumber と合わせて10になる値）
    @State private var incomingNumber:  Int     = 0
    // 飛んでくる数字の水平オフセット（offScreenLeading = 画面外左、0 = 中央付近）
    @State private var incomingOffsetX: CGFloat = -220  // Swift制約によりリテラル
    // 「+」記号の表示フラグ（incomingNumber が滑り込んだ後に出現）
    @State private var showPlus:        Bool    = false
    // 「10」の大きな表示フラグ（合計が10になった瞬間に切り替え）
    @State private var showTen:         Bool    = false
    // 「10」テキストのスケール（弾むアニメ用：1.0 → 1.08 → 1.0）
    @State private var tenScale:        CGFloat = 1.0
    // ✨スパークの不透明度（表示後すぐにフェードアウトする）
    @State private var sparkOpacity:    Double  = 0.0
    // ✨スパークの垂直オフセット（上に浮かびながら消えていく演出）
    @State private var sparkOffsetY:    CGFloat = 0
    // アニメループの世代番号。onAppear のたびにインクリメントし、
    // 古い世代の DispatchQueue コールバックを無効化してループの多重起動を防ぐ。
    @State private var loopGeneration:  Int     = 0

    var body: some View {
        VStack(spacing: 0) {

            // アニメーションカード（PlayingView の ProblemCard と同じ高さ・余白）
            // 「n + (10-n) = 10」の流れをループアニメで表示し、ゲームの内容を直感的に伝える。
            ZStack {
                DS.cardShadow()
                ZStack {
                    if showTen {
                        // 合計が10になった瞬間の表示：大きな「10」＋✨スパーク
                        Text("10")
                            .font(.system(size: 130, weight: .bold, design: .rounded))
                            .foregroundStyle(DS.primary)
                            // 弾むアニメ用スケール（tenScale が 1.0→1.08→1.0 と変化する）
                            .scaleEffect(tenScale)
                        // スパーク：上に浮かびながらフェードアウトする演出
                        Text("✨")
                            .font(.system(size: 26))
                            .offset(x: 74, y: -62 + sparkOffsetY)
                            .opacity(sparkOpacity)
                    } else {
                        // 通常表示：中央の数字（固定）と左から飛んでくる数字（可動）
                        Text("\(centerNumber)")
                            .font(.system(size: 130, weight: .bold, design: .rounded))
                            .foregroundStyle(DS.primary)
                            // incomingNumber が確定するまで非表示にして見た目を整える
                            .opacity(incomingNumber > 0 ? 1.0 : 0.0)
                        if incomingNumber > 0 {
                            // 飛んでくる数字と「+」記号を HStack で並べ、
                            // incomingOffsetX で画面外左から中央へスライドさせる
                            HStack(spacing: 6) {
                                Text("\(incomingNumber)")
                                    .font(.system(size: 90, weight: .bold, design: .rounded))
                                    .foregroundStyle(DS.accent)
                                if showPlus {
                                    // 「+」は数字が中央付近に到達してから遅れて表示（.opacity トランジション）
                                    Text("+")
                                        .font(.system(size: 72, weight: .medium, design: .rounded))
                                        .foregroundStyle(DS.muted)
                                        .transition(.opacity)
                                }
                            }
                            // -100 の追加オフセットで HStack 全体を左寄りに調整し、
                            // centerNumber テキストと重ならないようにする
                            .offset(x: incomingOffsetX - 100)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 200)
            .padding(.horizontal, 24)
            .padding(.top, 12)
            .padding(.bottom, 20)

            // ハイスコア表示（解放後のみ）
            // isHighScoreUnlocked が true になるまではこのブロック全体を非表示にする。
            // 初回プレイヤーに余計な情報を見せず、UI をシンプルに保つ意図。
            if viewModel.isHighScoreUnlocked {
                HStack(spacing: 8) {
                    Text("🏆").font(.system(size: 20))
                    Text("title_high_score_label")
                        .font(.system(size: 16, weight: .medium, design: .rounded))
                        .foregroundStyle(DS.muted)
                    // 実際のハイスコア値（blitz モードの最高得点）
                    Text("\(viewModel.blitzHighScore)")
                        .font(.system(size: 24, weight: .black, design: .rounded))
                        .foregroundStyle(DS.accent)
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: DS.sectionRadius)
                        .fill(DS.card)
                        .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 3)
                )
                .padding(.bottom, 16)
            }

            // ─── ボタンエリア ───────────────────────────────
            VStack(spacing: 12) {
                if viewModel.isBlitzUnlocked {
                    // 解放後：[３０びょう] [１０びょう] を横並び
                    // blitz モードが解放されたら2つのモードボタンを等幅で並べる
                    HStack(spacing: 12) {
                        ModeButton(label: "title_mode_normal_label", color: DS.primary) {
                            withAnimation { viewModel.startGame(mode: .normal) }
                        }
                        ModeButton(label: "title_mode_blitz_label", color: DS.blitzColor) {
                            withAnimation { viewModel.startGame(mode: .blitz) }
                        }
                    }
                } else {
                    // 解放前：[３０びょう] 全幅
                    // blitz 未解放時はノーマルモードのみ全幅で表示してシンプルさを保つ
                    ModeButton(label: "title_mode_normal_label", color: DS.primary) {
                        withAnimation { viewModel.startGame(mode: .normal) }
                    }
                }

                // クイズボタン（常に表示）
                // ゲームモードの解放状態に関わらず常に表示し、クイズへのアクセスを保証する
                ModeButton(label: "title_mode_other_games_label", color: DS.accent) {
                    onGamePicker()
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)

            Spacer()
        }
        .onAppear {
            // 世代番号を更新してから新しいループを開始する。
            // 画面が再表示されるたびにインクリメントすることで、
            // 前回の DispatchQueue コールバックが残っていても generation の不一致で
            // 自動的に無効化され、ループの多重起動を防ぐ。
            loopGeneration += 1
            runTitleLoop(generation: loopGeneration)
        }
    }

    // タイトルデモアニメのメインループ。
    // 「ランダムな数字が左から滑り込み → + 記号が出現 → 合計10が弾ける → リセット」
    // という一連のシーケンスを再帰呼び出しで繰り返す。
    // generation が現在の loopGeneration と一致しないコールバックは即座に抜けることで
    // 旧世代のタイマーが新しいループに干渉しないようにする。
    private func runTitleLoop(generation: Int) {
        // 世代が変わっていれば（画面離脱→再表示など）このループを中断
        guard generation == loopGeneration else { return }
        resetState()
        // 1〜9 のランダムな数字を中央に設定（足して10になる相手が決まる）
        let n = Int.random(in: 1...9)
        centerNumber = n

        // 0.8秒後：「足す数」を確定させ、左から中央へスライドイン開始
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            guard generation == self.loopGeneration else { return }
            self.incomingNumber = 10 - n
            withAnimation(.easeInOut(duration: 1.0)) { self.incomingOffsetX = 0 }

            // スライドイン開始から0.6秒後：「+」記号をフェードイン
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                guard generation == self.loopGeneration else { return }
                withAnimation(.easeInOut(duration: 0.35)) { self.showPlus = true }

                // 「+」出現から0.55秒後：「10」に切り替えてスパーク演出開始
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) {
                    guard generation == self.loopGeneration else { return }
                    withAnimation(.easeInOut(duration: 0.28)) {
                        self.showTen = true; self.sparkOpacity = 1.0
                    }
                    // 「10」出現から0.15秒後：スケールを1.08に拡大（弾む第1フェーズ）
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                        guard generation == self.loopGeneration else { return }
                        withAnimation(.easeInOut(duration: 0.28)) { self.tenScale = 1.08 }
                        // 拡大から0.28秒後：元のサイズ1.0に戻す（弾む第2フェーズ）
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.28) {
                            guard generation == self.loopGeneration else { return }
                            withAnimation(.easeInOut(duration: 0.28)) { self.tenScale = 1.0 }
                        }
                    }
                    // スパーク：0.8秒かけて上に浮かびながらフェードアウト（「10」表示と並行）
                    withAnimation(.easeInOut(duration: 0.8)) {
                        self.sparkOffsetY = -28; self.sparkOpacity = 0.0
                    }
                    // 「10」表示から1.2秒後：フェードアウトして状態をリセットし、次のループへ
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                        guard generation == self.loopGeneration else { return }
                        withAnimation(.easeInOut(duration: 0.35)) {
                            self.showTen = false; self.resetState()
                        }
                        // リセットアニメ完了後（0.45秒）に次のループを再帰呼び出し
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
                            self.runTitleLoop(generation: generation)
                        }
                    }
                }
            }
        }
    }

    // アニメーション用 State を初期値に戻すヘルパー。
    // ループの先頭と「10」フェードアウト時の両方から呼ばれる。
    // 複数箇所でのリセット処理をここに集約することで、リセット漏れを防ぐ。
    private func resetState() {
        incomingOffsetX = offScreenLeading; showPlus = false; showTen = false
        tenScale = 1.0; sparkOpacity = 0.0; sparkOffsetY = 0; incomingNumber = 0
    }
}

// MARK: - ModeButton

// タイトル画面のゲームモード選択ボタン。ラベル・色・アクションを外から注入する汎用コンポーネント。
// タップ時にバイブレーションとタップ音を自動で鳴らし、呼び出し側でのサウンド記述を不要にする。
struct ModeButton: View {
    // ローカライズキーを直接受け取ることで xcstrings による多言語対応に対応
    let label:  LocalizedStringKey
    // ボタン背景色（モードごとに異なる色を渡してブランドカラーを統一）
    let color:  Color
    // タップ時に実行するアクション（ゲーム開始・画面遷移などを呼び出し側が定義）
    let action: () -> Void

    var body: some View {
        Button {
            // タップ確定時：バイブ → タップ音 → アクション の順で実行
            SoundManager.shared.vibrate()
            SoundManager.shared.playTap()
            action()
        } label: {
            Text(label)
                .font(.system(size: 26, weight: .black, design: .rounded))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)   // 親の幅いっぱいに広がり、横並び時も等幅になる
                .padding(.vertical, 20)
                .background(
                    RoundedRectangle(cornerRadius: DS.btnRadius)
                        .fill(color)
                        // ボタン色と同色の影で立体感を演出（色が変わっても影が浮かない）
                        .shadow(color: color.opacity(0.35), radius: 8, x: 0, y: 4)
                )
        }
        // .plain スタイルでデフォルトのハイライト挙動を無効化し、
        // 背景の RoundedRectangle だけで見た目を完全にコントロールする
        .buttonStyle(.plain)
    }
}
