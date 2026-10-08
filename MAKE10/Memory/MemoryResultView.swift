//
//  MemoryResultView.swift
//  FDL-TenBlitz
//
//  Created by 空飛ぶ研究室(FlyingDevLab) on 2026/09/06.
//

// どうぶつめくりのクリア後画面。今回もらったエネルギーを見せ、動物10種から好きなシールを1匹選ぶ。
//
// ★ ごほうびは2つ ★
//   ① エネルギー … そろえるたびに（連続ならコンボボーナス付きで）その場で増えている
//                  （MemoryGameEngine.grantMatchReward を参照）。
//                  この画面は EnergyRewardBanner で「今回いくら増えたか」を見せるだけで、残高には触らない。
//   ② シール     … クリアのごほうびとして、好きな動物を「自分で選ぶ」。
//                  選ばれた1匹を StickerStore.addStickerToStorage() でストレージへ直接入れる
//                  （ガチャ・ショップで手に入れたシールと同じ行き先）。
//
// ★ ストレージ直送にした理由 ★
//   ストレージには上限がないため、必ず成功します。
//   その代わりシールはその場に現れないので、
//   「シールばこに いれたよ」の一行で行き先を伝えます。
//
// ★ タップで即確定にしている理由 ★
//   直前まで連打を前提としたゲームを遊んでいるため、テンポを止めたくないこと。
//   そして重複が許され、遊び直しが無制限で、ストレージにも上限がないため、
//   押し間違えても実際に失われるものが無いことの2点です。
//   確認ステップの代わりに、表示直後の入力ガードと、選んだ後の反応を厚くしています。

import SwiftUI

// MARK: - MemoryResultView

struct MemoryResultView: View {

    // MARK: 設定項目（呼び出し側から渡すパラメータ）

    /// 「もういちど」が押されたときに呼ばれる。盤面の作り直しは呼び出し側が行う。
    let onPlayAgain: () -> Void

    // MARK: 調整用の定数

    /// ボタンに使うテーマ色。MemoryGameView と同じ値にすること。
    private let themeColor = Color.brown   // ← 変更可（タイル色と揃えること）

    /// シールを選んでから「もういちど」が現れるまでの間（秒）。
    private let revealHold: TimeInterval = 0.80   // ← 変更可

    /// 選択グリッドの横幅の上限。iPad で1枚が大きくなりすぎないようにする。
    private let chooserMaxWidth: CGFloat = 460    // ← 変更可

    // MARK: 状態

    /// 選ばれた動物。nil のあいだは選択グリッドを表示する。
    @State private var chosen: MemoryAnimal? = nil

    // ★ 入力ガードについて ★
    //   このゲームは連打を前提に作られているため、クリア直後も指が動き続けています。
    //   何もしないと、画面が出た瞬間のタップで中身を見る前に決まってしまいます。
    //   FinishedView・JankenResultView と同じ作法で、表示から一定時間は受け付けません。

    /// 入力を受け付けてよいか。表示から selectTapGuard 秒後に true になる。
    @State private var canTap = false

    /// 「もういちど」を表示してよいか。選択の余韻を見せてから出す。
    @State private var showPlayAgain = false

    // MARK: body

    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            VStack(spacing: 8) {
                Text(verbatim: "🎉")
                    .font(.system(size: 60))   // ← 変更可

                Text("memory_clear_congrats")
                    .font(.system(size: 28, weight: .black, design: .rounded))  // ← 変更可
                    .foregroundStyle(DS.textPrimary)
            }
            .wallpaperCushion()   // かべがみの上でも読めるように（DesignSystem.swift を参照）

            EnergyRewardBanner()

            ZStack {
                if let animal = chosen {
                    chosenContent(animal)
                        .transition(.scale(scale: 0.85).combined(with: .opacity))
                } else {
                    chooserContent
                        .transition(.opacity)
                }
            }

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
                canTap = true
            }
        }
    }

    // MARK: - 選択グリッド

    private var chooserContent: some View {
        VStack(spacing: 14) {
            Text("memory_result_choose")
                .font(.system(size: 20, weight: .bold, design: .rounded))  // ← 変更可（見出しサイズ）
                .foregroundStyle(DS.textPrimary)
                .multilineTextAlignment(.center)
                .wallpaperCushion()
                .padding(.horizontal, 24)

            // 盤面と同じ5列にして、続きの画面であることを見た目でも揃える。
            LazyVGrid(
                columns: Array(
                    repeating: GridItem(.flexible(), spacing: MemoryTuning.cardSpacing),
                    count: MemoryTuning.columns
                ),
                spacing: MemoryTuning.cardSpacing
            ) {
                ForEach(MemoryAnimal.allCases, id: \.self) { animal in
                    animalTile(animal)
                }
            }
            .frame(maxWidth: chooserMaxWidth)
            .padding(.horizontal, MemoryTuning.boardPadding)
        }
    }

    /// 選択グリッドのタイル1枚。辺の長さは列の幅で決まる（正方形）。
    private func animalTile(_ animal: MemoryAnimal) -> some View {
        RoundedRectangle(cornerRadius: MemoryTuning.cardCornerRadius)
            .fill(DS.card)
            .aspectRatio(1, contentMode: .fit)
            .overlay(
                GeometryReader { geo in
                    Text(animal.emoji)
                        .font(.system(size: geo.size.width * 0.55))   // ← 変更可（辺長に対する絵文字の比率）
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            )
            .shadow(color: .black.opacity(0.08), radius: 4, x: 0, y: 2)
            .contentShape(Rectangle())
            .onTapGesture { choose(animal) }
            .accessibilityElement()
            .accessibilityLabel(Text(animal.accessibilityLabel))
            .accessibilityAddTraits(.isButton)
    }

    // MARK: - 選択後

    /// 選んだ動物を大きく見せ、行き先を伝える。
    private func chosenContent(_ animal: MemoryAnimal) -> some View {
        VStack(spacing: 12) {
            Text(animal.emoji)
                .font(.system(size: 100))   // ← 変更可（選んだ動物の表示サイズ）
                .accessibilityLabel(Text(animal.accessibilityLabel))

            Text("memory_result_saved")
                .font(.system(size: 18, weight: .bold, design: .rounded))  // ← 変更可
                .foregroundStyle(DS.muted)
        }
        .wallpaperCushion()
    }

    // MARK: - 選択の処理

    // ★ シールを先に渡している理由 ★
    //   演出を待ってから付与すると、その途中で画面を離れたときにシールが消えます。
    //   タップされた時点で確定させ、演出はその後に流します。

    /// 動物が選ばれたときの処理。シールを付与し、表示を切り替える。
    private func choose(_ animal: MemoryAnimal) {
        // 入力ガード中、および選択済みのときは受け付けない。
        guard canTap, chosen == nil else { return }

        StickerStore.shared.addStickerToStorage(emoji: animal.emoji)

        SoundManager.shared.vibrate()
        SoundManager.shared.playUnlock()

        withAnimation(.spring(response: 0.45, dampingFraction: 0.70)) {
            chosen = animal
        }

        // 余韻を見せてから出す。選択直後に出すと、その勢いで押されてしまう。
        DispatchQueue.main.asyncAfter(deadline: .now() + revealHold) {
            withAnimation(.easeOut(duration: 0.30)) {
                showPlayAgain = true
            }
        }
    }
}
