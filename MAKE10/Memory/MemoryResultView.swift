//
//  MemoryResultView.swift
//  FDL-TenBlitz
//
//  Created by 空飛ぶ研究室(FlyingDevLab) on 2026/09/06.
//

// どうぶつめくりのクリア後画面。今回もらったエネルギーを見せて、もういちど遊べるようにする。
//
// ★ エネルギーは盤面で渡し済み ★
//   このゲームはクリアボーナスを持たず、そろえるたびに（連続ならコンボボーナス付きで）
//   その場でエネルギーが増える（MemoryGameEngine.grantMatchReward を参照）。
//   この画面は EnergyRewardBanner で「今回いくら増えたか」を見せるだけで、残高には触らない。

import SwiftUI

// MARK: - MemoryResultView

struct MemoryResultView: View {

    // MARK: 設定項目（呼び出し側から渡すパラメータ）

    /// 「もういちど」が押されたときに呼ばれる。盤面の作り直しは呼び出し側が行う。
    let onPlayAgain: () -> Void

    // MARK: 調整用の定数

    /// ボタンに使うテーマ色。MemoryGameView と同じ値にすること。
    private let themeColor = Color.brown   // ← 変更可（タイル色と揃えること）

    // MARK: 状態

    // ★ 入力ガードについて ★
    //   このゲームは連打を前提に作られているため、クリア直後も指が動き続けています。
    //   何もしないと、画面が出た瞬間のタップで「もういちど」が押されてしまいます。
    //   FinishedView・JankenResultView と同じ作法で、表示から一定時間は出しません。

    /// 「もういちど」を表示してよいか。表示から selectTapGuard 秒後に true になる。
    @State private var showPlayAgain = false

    // MARK: body

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Text(verbatim: "🎉")
                .font(.system(size: 90))   // ← 変更可

            Text("memory_clear_congrats")
                .font(.system(size: 30, weight: .black, design: .rounded))  // ← 変更可
                .foregroundStyle(DS.textPrimary)

            EnergyRewardBanner()

            Spacer()

            Button {
                SoundManager.shared.vibrate()
                SoundManager.shared.playTap()
                onPlayAgain()
            } label: {
                Text("memory_result_again")
                    .font(.system(size: 24, weight: .black, design: .rounded))  // ← 変更可
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 18)   // ← 変更可（ボタン縦パディング）
                    .background(
                        RoundedRectangle(cornerRadius: DS.btnRadius)
                            .fill(themeColor)
                            .shadow(color: themeColor.opacity(0.35), radius: 8, x: 0, y: 4)
                    )
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
            .opacity(showPlayAgain ? 1 : 0)        // 場所は先に取っておき、出たときにレイアウトが跳ねないようにする
            .allowsHitTesting(showPlayAgain)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + MemoryTuning.selectTapGuard) {
                withAnimation(.easeOut(duration: 0.30)) { showPlayAgain = true }
            }
        }
    }
}
