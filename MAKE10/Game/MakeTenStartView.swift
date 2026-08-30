//
//  MakeTenStartView.swift
//  FDL-TenBlitz
//
//  Created by KatoMasaru on 2026/08/30.
//

// MAKE10 のスタート画面（gameState == .starting のとき表示される）を定義するファイル。
// 遊び方の説明・そのモードの最高記録・スタートボタンを表示する。
//
// ★ この画面を追加した理由 ★
//   もぐら叩き・迷路・ピンボール等は「説明カード → 記録 → スタートボタン」という
//   スタート画面を持っているが、MAKE10 だけはタイルをタップすると即ゲームが
//   始まる作りだった。そのため遊ぶ前に自分の記録を確認する場所がなかった。
//   他のゲームと画面構成を揃えることで、アプリ全体の操作感を統一している。
//
// ★ 画面遷移の流れ ★
//   TitleView のタイルをタップ
//     → GameViewModel.showStartScreen(mode:) が gameMode と gameState(.starting) を更新
//     → MakeTenContentView がこの画面を表示
//     → 「ゲームスタート」ボタンで GameViewModel.startGame(mode:) を呼ぶ
//     → gameState が .playing になり PlayingView へ
//   ヘッダー左の戻るボタン（SharedFrame が描画）でタイトルへ戻れる。
//
// ★ 記録の表示について ★
//   viewModel.currentHighScore は gameMode に応じて
//   normalHighScore（30びょう）と blitzHighScore（10びょう）を出し分ける。
//   showStartScreen(mode:) で gameMode が確定済みなので、ここでは意識しなくてよい。
//   記録が 0（未プレイ）のときは記録欄そのものを表示しない。
//   これは他のゲームのスタート画面と同じ条件（highScore > 0）に揃えたもの。

import SwiftUI

// MARK: - MakeTenStartView

struct MakeTenStartView: View {

    // MARK: 依存（呼び出し側から渡すパラメータ）

    var viewModel: GameViewModel

    // MARK: 表示の出し分け

    /// Blitz（10びょう）モードかどうか。色と説明文の切り替えに使う。
    private var isBlitz: Bool { viewModel.gameMode == .blitz }

    /// モードを表すメインカラー。10びょうは赤系、30びょうは青系。
    /// PlayingView / FinishedView と同じ配色にして、モードの見分けを一貫させている。
    private var mainColor: Color { isBlitz ? DS.blitzColor : DS.primary }

    /// 説明カードの1行目。制限時間の案内はモードごとに変わる。
    private var timeLineKey: LocalizedStringKey {
        isBlitz ? "maketen_howto_time_blitz" : "maketen_howto_time_normal"
    }

    /// 説明カードの1行目に添える絵文字。
    private var timeLineEmoji: String {
        isBlitz ? "⚡️" : "⏱️"   // ← 変更可（タイトル画面のタイル絵文字と揃えている）
    }

    // MARK: body

    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            // ── 遊び方カード ──────────────────────────────────
            // 4行構成。1行目のみモードで出し分け、2〜4行目は両モード共通。
            // ⚠️ 変更注意: 3行目（コンボ）と4行目（ペナルティ）は
            //   GameViewModel の comboBonusTime / C.wrongPenalty の挙動を説明している。
            //   仕様を変えるときは文言（xcstrings）も合わせて見直すこと。
            VStack(alignment: .leading, spacing: 12) {
                Label("How to Play", systemImage: "questionmark.circle.fill")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(DS.muted)

                howToRow(emoji: timeLineEmoji, textKey: timeLineKey)
                howToRow(emoji: "🔢", textKey: "maketen_howto_rule")
                howToRow(emoji: "🔥", textKey: "maketen_howto_combo")
                howToRow(emoji: "⏳", textKey: "maketen_howto_penalty")
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(DS.card, in: RoundedRectangle(cornerRadius: DS.sectionRadius))
            .padding(.horizontal, 24)

            // ── ハイスコア（記録がある場合のみ表示）──────────
            // 未プレイ（0）のときは欄ごと出さない。他ゲームのスタート画面と同じ条件。
            if viewModel.currentHighScore > 0 {
                HStack(spacing: 8) {
                    Text("🏆").font(.system(size: 20))
                    Text("title_high_score_label")
                        .font(.system(size: 16, weight: .medium, design: .rounded))
                        .foregroundStyle(DS.muted)
                    Text("\(viewModel.currentHighScore)")
                        .font(.system(size: 24, weight: .black, design: .rounded))  // ← 変更可（数値サイズ）
                        .foregroundStyle(DS.accent)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .background(DS.card, in: RoundedRectangle(cornerRadius: DS.sectionRadius))
            }

            Spacer()

            // ── スタートボタン ────────────────────────────────
            // startGame には現在の gameMode を明示的に渡す。
            // 引数を省略すると既定値の .normal になり、10びょうを選んでいても
            // 30びょうが始まってしまうため、必ず mode を指定すること。
            Button {
                SoundManager.shared.vibrate()
                SoundManager.shared.playTap()
                withAnimation { viewModel.startGame(mode: viewModel.gameMode) }
            } label: {
                Text("ゲームスタート")
                    .font(.system(size: 26, weight: .black, design: .rounded))  // ← 変更可（ボタン文字サイズ）
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)                                      // ← 変更可（ボタン縦パディング）
                    .background(
                        RoundedRectangle(cornerRadius: DS.btnRadius)
                            .fill(mainColor)
                            .shadow(color: mainColor.opacity(0.35), radius: 8, x: 0, y: 4)
                    )
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
    }

    // MARK: 部品

    /// 説明カードの1行（絵文字 + 説明文）を組み立てる。
    /// 絵文字は装飾なので翻訳対象に含めず、コード側で指定している。
    /// alignment: .top にしているのは、文が2行に折り返しても絵文字が先頭行に揃うようにするため。
    private func howToRow(emoji: String, textKey: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(emoji).font(.system(size: 18))
            Text(textKey)
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .foregroundStyle(DS.textPrimary)
        }
    }
}
