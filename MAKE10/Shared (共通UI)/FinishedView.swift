//
//  FinishedView.swift
//  FDL-TenBlitz
//
//  Created by 空飛ぶ研究室(FlyingDevLab) on 2026/03/08.
//

// ゲーム終了時に表示する結果画面と、シールチップのドラッグUIを定義するファイル。
// スコア表示・ハイスコア更新・Blitzモード解放バナー・シール獲得バナーを状況に応じて表示する。
//
// ★ このファイルの構成 ★
//   FinishedView                … 結果画面本体（カード・各種バナー・ボタン）
//   DraggablePendingStickerChip … バナー内のドラッグ可能なシールチップ
//
// ★ シールがこの画面に届くまでの流れ ★
//   ① プレイ中: GameViewModel が正解ごとに StickerStore.recordCorrect() を呼ぶ
//   ② StickerStore がポイントを貯め、シール獲得時に pendingStickers（ボード行き）へ積む。
//      ただしゲームボードが満杯（50枚以上）なら pendingStorageCount（ストレージ行き）に回す
//   ③ この画面の onAppear で両方を読み取り、バナーとして表示する
//   ④ ボード行きシールは「ドラッグで好きな場所に配置」または
//      「画面を離れるときにバナー上の位置へ自動配置」される（シールをロストしない設計）

import SwiftUI

// MARK: - FinishedView

struct FinishedView: View {

    // MARK: 依存

    var viewModel: GameViewModel

    // MARK: ローカル状態

    /// 結果カードのポップインアニメーション用。onAppear で 1.0・1.0 に向けてアニメーションする。
    @State private var scale:   CGFloat = 0.75
    @State private var opacity: Double  = 0.0

    /// 誤タップ防止フラグ。アニメーション完了後（1秒後）に true になりボタンが有効化される。
    @State private var canTap:  Bool    = false

    /// 今回のゲームで獲得したシールの絵文字リスト（ゲームボード行き）。
    /// バナーに表示し、ドラッグで配置できる。
    @State private var newStickerEmojis: [String] = []

    /// ストレージへ送出されたシール枚数。0より大きいときにストレージ通知バナーを表示する。
    @State private var storageSentCount: Int = 0

    /// バナー内の各絵文字チップのグローバル座標（index → CGPoint）。
    /// ドラッグしなかった場合の自動配置のために、チップの表示位置を記録しておく。
    @State private var capturedPositions: [Int: CGPoint] = [:]

    /// 座標をスクリーン比率に変換するためのスクリーンサイズ参照。
    private var screenSize: CGSize { UIScreen.main.bounds.size }

    // MARK: body

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            // ── 結果カード ──────────────────────────────────
            // スコアが0のときは称賛テキストのみ、1以上のときはスコア数字も大きく表示する
            VStack(spacing: 12) {
                if viewModel.score == 0 {
                    // 0問正解のときはスコア数字を出さず、励ましのメッセージだけを表示する
                    Text(viewModel.praiseText)
                        .font(.system(size: 38, weight: .bold, design: .rounded))
                        .foregroundStyle(DS.primary)
                        .multilineTextAlignment(.center)
                } else {
                    Text("finished_correct_label")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundStyle(DS.accent)

                    // スコア数字。Blitzモードは赤系、通常モードは青系のグラデーションで区別する
                    Text("\(viewModel.score)")
                        .font(.system(size: 120, weight: .black, design: .rounded))
                        .foregroundStyle(LinearGradient(
                            colors: [
                                viewModel.gameMode == .blitz ? DS.blitzColor : DS.primary,
                                DS.accent
                            ],
                            startPoint: .top, endPoint: .bottom
                        ))
                        .scaleEffect(1.05)
                        .shadow(color: DS.primary.opacity(0.25), radius: 8, x: 0, y: 4)

                    Text(viewModel.praiseText)
                        .font(.system(size: 44, weight: .bold, design: .rounded))
                        .foregroundStyle(DS.primary)
                        .multilineTextAlignment(.center)

                    // Blitzモードかつ解放済みのときのみハイスコアセクションを表示する
                    if viewModel.gameMode == .blitz && viewModel.isHighScoreUnlocked {
                        Divider().padding(.horizontal, 20)
                        if viewModel.isNewHighScore {
                            // 今回が新記録のとき。ゴールドカラーで更新を強調する
                            Text("finished_high_score_updated")
                                .font(.system(size: 18, weight: .bold, design: .rounded))
                                .foregroundStyle(DS.gold)
                        } else {
                            // 更新なしのとき。現在のハイスコアをサブ表示として静かに添える
                            HStack(spacing: 6) {
                                Text("finished_high_score_label")
                                    .font(.system(size: 15, weight: .medium, design: .rounded))
                                    .foregroundStyle(DS.muted)
                                Text("\(viewModel.blitzHighScore)")
                                    .font(.system(size: 22, weight: .black, design: .rounded))
                                    .foregroundStyle(DS.accent)
                            }
                        }
                    }
                }
            }
            .padding(.vertical, 40)
            .padding(.horizontal, 36)
            .background(DS.cardShadow())
            .clipShape(RoundedRectangle(cornerRadius: DS.cardRadius))
            .padding(.horizontal, 28)
            // onAppear で 0.75→1.0 にアニメーションするポップインエフェクト
            .scaleEffect(scale)
            .opacity(opacity)

            Spacer()

            // ── Blitzモード解放バナー ────────────────────────
            // 初めて Blitz が解放されたセッションのみ表示する
            if viewModel.showUnlockBanner {
                VStack(spacing: 4) {
                    Text("finished_unlock_title")
                        .font(.system(size: 24, weight: .black, design: .rounded))
                        .foregroundStyle(DS.blitzColor)
                    Text("finished_unlock_message")
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        .foregroundStyle(DS.textBody)
                }
                .padding(.vertical, 14)
                .padding(.horizontal, 28)
                .background(
                    RoundedRectangle(cornerRadius: DS.sectionRadius)
                        .fill(DS.card)
                        .shadow(color: .black.opacity(0.08), radius: 10, x: 0, y: 4)
                )
                .padding(.bottom, 16)
                .transition(.scale.combined(with: .opacity))
            }

            // ── ストレージ送出バナー ──────────────────────────
            // ゲームボードが満杯でシールがストレージへ送られたときに表示する。
            // ドラッグ配置UIは不要。メッセージのみで通知する。
            if storageSentCount > 0 {
                HStack(spacing: 10) {
                    Text("📦")
                        .font(.system(size: 28))
                    Text("sticker_sent_to_storage")
                        .font(.system(size: 15, weight: .black, design: .rounded))
                        .foregroundStyle(DS.primary)
                }
                .padding(.vertical, 14)
                .padding(.horizontal, 20)
                .frame(maxWidth: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: DS.sectionRadius)
                        .fill(DS.card)
                        .shadow(color: DS.primary.opacity(0.12), radius: 10, x: 0, y: 4)
                )
                .padding(.horizontal, 28)
                .padding(.bottom, 16)
                .transition(.scale(scale: 0.85).combined(with: .opacity))
            }

            // ── 新着シールバナー ──────────────────────────────
            // ゲームボード行きのシールがある場合のみ表示する
            if !newStickerEmojis.isEmpty {
                VStack(spacing: 8) {
                    // 獲得枚数に応じてメッセージを単数形・複数形で切り替える
                    Text("Got \(newStickerEmojis.count) Stickers!")
                        .font(.system(size: 15, weight: .black, design: .rounded))
                        .foregroundStyle(DS.primary)
                    HStack(spacing: 4) {
                        ForEach(Array(newStickerEmojis.enumerated()), id: \.offset) { idx, emoji in
                            // ドラッグで盤面に配置できるシールチップ。
                            // ドラッグ完了コールバックで配列から該当シールを削除する
                            DraggablePendingStickerChip(emoji: emoji) {
                                if let i = newStickerEmojis.firstIndex(of: emoji) {
                                    withAnimation(.easeIn(duration: 0.15)) {
                                        newStickerEmojis.remove(at: i)
                                        capturedPositions.removeValue(forKey: idx)
                                    }
                                }
                            }
                            // ★ 見えない背景でViewの画面上の座標を取得するテクニック ★
                            //   GeometryReader を background に仕込むと、このチップと同じ
                            //   サイズ・位置の「透明な層」ができます。そこから
                            //   frame(in: .global) で画面全体（グローバル）座標系での
                            //   位置を読み取れます。SwiftUI で「このViewは画面のどこに
                            //   いるか」を知りたいときの定番パターンです。
                            .background(
                                GeometryReader { chipGeo in
                                    Color.clear.onAppear {
                                        let frame = chipGeo.frame(in: .global)
                                        capturedPositions[idx] = CGPoint(x: frame.midX, y: frame.midY)
                                    }
                                }
                            )
                        }
                    }
                    Text("Drag to Move")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(DS.muted)
                }
                .padding(.vertical, 14)
                .padding(.horizontal, 20)
                .frame(maxWidth: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: DS.sectionRadius)
                        .fill(DS.card)
                        .shadow(color: DS.primary.opacity(0.12), radius: 10, x: 0, y: 4)
                )
                .padding(.horizontal, 28)
                .padding(.bottom, 16)
                .transition(.scale(scale: 0.85).combined(with: .opacity))
            }

            // ── 「もう一度」ボタン ────────────────────────────
            // canTap が true になるまでは無効化してアニメーション中の誤タップを防ぐ。
            // ボタン色はゲームモードに合わせて Blitz=赤系、通常=青系に切り替える
            Button {
                guard canTap else { return }
                placeRemainingStickers()
                withAnimation { viewModel.startGame(mode: viewModel.gameMode) }
            } label: {
                let color = viewModel.gameMode == .blitz ? DS.blitzColor : DS.primary
                Label("finished_play_again_button", systemImage: "arrow.counterclockwise")
                    .font(.system(size: 18, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 18)
                    .background(
                        RoundedRectangle(cornerRadius: DS.btnRadius)
                            .fill(color)
                            .shadow(color: color.opacity(0.35), radius: 8, x: 0, y: 4)
                    )
            }
            .buttonStyle(.plain)
            .disabled(!canTap)
            .padding(.horizontal, 28)
            .padding(.bottom, 12)

            // ── 「もどる」ボタン ──────────────────────────────
            // Blitzモードが解放済みのときのみ表示する。
            // 未解放時は Spacer で同等の高さを確保してレイアウトが崩れないようにする
            if viewModel.isBlitzUnlocked {
                Button {
                    guard canTap else { return }
                    placeRemainingStickers()
                    withAnimation { viewModel.returnToTitle() }
                } label: {
                    Text("finished_back_button")
                        .font(.system(size: 18, weight: .semibold, design: .rounded))
                        .foregroundStyle(DS.muted)
                        .padding(.horizontal, 36)
                        .padding(.vertical, 11)
                        .background(Capsule().fill(Color.black.opacity(0.05)))
                }
                .buttonStyle(.plain)
                .disabled(!canTap)
                .padding(.bottom, 24)
            } else {
                // Blitz未解放時はボタンの代わりに Spacer で同じ高さを確保する
                Spacer().frame(height: 24)
            }
        }
        .onAppear {
            // 結果カードをスケール＋フェードでポップインさせる
            withAnimation(.easeOut(duration: 0.45)) {
                scale   = 1.0
                opacity = 1.0
            }
            // アニメーション完了後1秒でボタンを有効化し、演出中の誤タップを防ぐ
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {   // ← 変更可（誤タップ防止の秒数）
                canTap = true
            }

            let store = StickerStore.shared

            // ゲームボード行きのシールがあればバナーをスプリングアニメーションで表示する
            if !store.pendingStickers.isEmpty {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.65)) {
                    newStickerEmojis = store.pendingStickers
                }
            }

            // ストレージへ送出されたシールがあれば枚数を記録してバナーを表示する。
            // 読み取り後すぐにリセットし、次回表示への持ち越しを防ぐ
            if store.pendingStorageCount > 0 {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.65)) {
                    storageSentCount = store.pendingStorageCount
                }
                store.clearPendingStorage()
            }
        }
        .onDisappear {
            // Viewが消える直前に残留シールを自動配置する。
            // ボタン操作以外で画面を離れた場合もシールをロストしないための安全策
            placeRemainingStickers()
        }
    }

    // MARK: シール配置

    /// ドラッグされなかった残りのシールを、バナー上の表示位置にそのまま配置する。
    ///
    /// ★ なぜ座標を「比率」で保存するのか ★
    ///   ピクセル座標のまま保存すると、別のサイズの端末（に機種変更した場合など）で
    ///   シールが画面外に出てしまいます。スクリーンサイズに対する比率（0.0〜1.0）に
    ///   変換しておけば、どの端末でも「画面のだいたい同じ場所」に復元できます。
    ///
    /// ⚠️ 変更注意: クランプ範囲 0.08〜0.92 は DraggablePendingStickerChip の
    ///   onEnded 内にも同じ値がある。変えるときは両方を揃えること
    ///   （ずれるとドラッグ配置と自動配置で可動範囲が変わってしまう）。
    private func placeRemainingStickers() {
        for (idx, emoji) in newStickerEmojis.enumerated() {
            if let pos = capturedPositions[idx] {
                // バナー上の実座標 → 比率に変換してボードへ追加
                StickerStore.shared.placePendingSticker(
                    emoji: emoji,
                    xRatio: max(0.08, min(0.92, pos.x / screenSize.width)),
                    yRatio: max(0.08, min(0.92, pos.y / screenSize.height))
                )
            } else {
                // 座標未取得の場合は従来のデフォルト配置にフォールバック
                StickerStore.shared.confirmPendingStickers()
            }
        }
        // 配置処理完了後にローカル状態をクリアして二重配置を防ぐ
        newStickerEmojis  = []
        capturedPositions = [:]
    }
}

// MARK: - DraggablePendingStickerChip

/// 結果画面のシールバナー内に表示するドラッグ可能なシールチップ。
/// ドラッグ終了時にドロップ座標を StickerStore に送り、ボード上に配置する。
/// 配置完了後はアニメーションで縮小・フェードアウトし、onPlaced コールバックで親に通知する。
struct DraggablePendingStickerChip: View {
    let emoji: String

    /// ドラッグ完了時に親Viewへ通知するコールバック。親はこれを受けて配列から自身を削除する。
    let onPlaced: () -> Void

    /// ドラッグ中のオフセット。DragGesture の translation を直接反映する。
    @State private var dragOffset: CGSize = .zero

    /// ドラッグ中フラグ。true のときにスケールアップ＋シャドウでつまみ上げた感を演出する。
    @State private var isDragging: Bool   = false

    /// 配置完了フラグ。true になるとスケール縮小＋フェードアウトのアニメーションが走る。
    @State private var isPlaced:   Bool   = false

    /// ドロップ座標をスクリーン比率に変換するために使用する。
    private var screenSize: CGSize { UIScreen.main.bounds.size }

    var body: some View {
        Text(emoji)
            .font(.system(size: 36))
            // ドラッグ中は1.35倍に拡大、配置後は0.5倍に縮小してから消える
            .scaleEffect(isDragging ? 1.35 : (isPlaced ? 0.5 : 1.0))   // ← 変更可（つまみ上げ拡大率）
            // 配置後はフェードアウトする
            .opacity(isPlaced ? 0 : 1)
            .offset(dragOffset)
            // ドラッグ中のみシャドウを付けて浮き上がり感を演出する
            .shadow(
                color: isDragging ? .black.opacity(0.22) : .clear,
                radius: 8, x: 0, y: 4
            )
            .animation(.spring(response: 0.22, dampingFraction: 0.55), value: isDragging)
            .animation(.easeIn(duration: 0.15), value: isPlaced)
            .gesture(
                // coordinateSpace: .global = 座標をこのView基準ではなく
                // 画面全体基準で受け取る（ドロップ位置を画面比率に変換するため）
                DragGesture(coordinateSpace: .global)
                    .onChanged { value in
                        // ドラッグ開始時（初回のonChanged）にのみバイブを鳴らしてつかんだことを伝える
                        if !isDragging {
                            isDragging = true
                            SoundManager.shared.vibrate()
                        }
                        dragOffset = value.translation
                    }
                    .onEnded { value in
                        isDragging = false
                        let loc = value.location
                        // ドロップ座標をスクリーン比率に変換し、8%〜92%にクランプして端への配置を防ぐ
                        // ⚠️ 変更注意: 0.08/0.92 は FinishedView.placeRemainingStickers と揃えること
                        let xRatio = max(0.08, min(0.92, loc.x / screenSize.width))
                        let yRatio = max(0.08, min(0.92, loc.y / screenSize.height))
                        StickerStore.shared.placePendingSticker(
                            emoji: emoji,
                            xRatio: xRatio,
                            yRatio: yRatio
                        )
                        // 配置アニメーションを開始してから onPlaced で親に通知する
                        withAnimation(.easeIn(duration: 0.15)) { isPlaced = true }
                        onPlaced()
                    }
            )
    }
}
