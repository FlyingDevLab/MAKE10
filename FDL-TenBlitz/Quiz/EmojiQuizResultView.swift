//
//  EmojiQuizResultView.swift
//  FDL-TenBlitz
//
//  Created by 空飛ぶ研究室(FlyingDevLab) on 2026/03/08.
//

// 絵文字クイズ終了後に表示する結果画面。
// スコア・メッセージ・円形ゲージで結果を視覚的に伝え、
// 獲得したシールのバナー表示とドラッグ配置への誘導も担う。

import SwiftUI

struct EmojiQuizResultView: View {
    var viewModel: EmojiQuizViewModel

    // 今回のクイズで新たに獲得したシールの絵文字リスト。
    // onAppearでStickerStore.pendingStickersから取得し、バナーに表示する
    @State private var newStickerEmojis: [String] = []

    /// バナー内の各絵文字チップのグローバル座標（index → CGPoint）
    // ドラッグせずに「もう一度」を押した場合に、バナー上の表示位置へシールを自動配置するために使う
    @State private var capturedPositions: [Int: CGPoint] = [:]

    // placeRemainingStickers内で座標をスクリーン比率に変換するために使用する
    private var screenSize: CGSize { UIScreen.main.bounds.size }

    // 正解数を総問題数で割った正答率（0〜100の整数）。
    // 各表示要素（絵文字・メッセージ・色）の分岐条件として使われる
    private var percentage: Int {
        guard viewModel.totalCount > 0 else { return 0 }
        return Int(Double(viewModel.score) / Double(viewModel.totalCount) * 100)
    }

    // 正答率に応じた結果絵文字を返す。100%なら🏆、以降スコアが下がるにつれ控えめな絵文字になる
    private var resultEmoji: String {
        switch percentage {
        case 100:       return "🏆"
        case 90..<100:  return "🎉"
        case 70..<90:   return "🌟"
        case 50..<70:   return "✨"
        case 30..<50:   return "😊"
        case 1..<30:    return "⭐"
        default:        return "🌈"
        }
    }

    // 正答率に応じたローカライズ済みの結果メッセージを返す。
    // percentageの閾値はresultEmojiと揃えて一貫性を保っている
    private var resultMessage: String {
        switch percentage {
        case 100:       return String(localized: "quiz_result_perfect")
        case 90..<100:  return String(localized: "quiz_result_excellent")
        case 70..<90:   return String(localized: "quiz_result_great")
        case 50..<70:   return String(localized: "quiz_result_good")
        case 30..<50:   return String(localized: "quiz_result_nice_try")
        case 1..<30:    return String(localized: "quiz_result_keep_going")
        default:        return String(localized: "quiz_result_try_again")
        }
    }

    // 正答率に応じてスコア数字と円形ゲージの色を変える。
    // 80%以上は緑（良好）、50%以上は金、それ以外はプライマリカラー
    private var scoreColor: Color {
        switch percentage {
        case 80...: return DS.gaugeFull
        case 50...: return DS.gold
        default:    return DS.primary
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            // 結果カード：絵文字＋メッセージ＋円形スコアゲージをまとめたメインコンテンツ
            VStack(spacing: 20) {
                VStack(spacing: 8) {
                    // 正答率に連動した結果絵文字。フォントサイズ72ptで画面の主役として表示する
                    Text(resultEmoji)
                        .font(.system(size: 72))
                    Text(resultMessage)
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                        .foregroundStyle(DS.primary)
                }
                Divider()

                // 円形スコアゲージ。正答率をパーセントに変換してCircle.trimで弧の長さを表現する
                ZStack {
                    // ゲージの背景トラック（薄いグレーの全円）
                    Circle()
                        .stroke(DS.gaugeBg, lineWidth: 12)

                    // 正答率ぶんだけ弧を描く前景トラック。
                    // -90度回転して12時方向からスタートするよう補正している
                    Circle()
                        .trim(from: 0, to: CGFloat(percentage) / 100)
                        .stroke(scoreColor, style: StrokeStyle(lineWidth: 12, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .animation(.easeOut(duration: 0.8), value: percentage)

                    // ゲージ中央に正解数と総問題数を重ねて表示する
                    VStack(spacing: 2) {
                        // 正解数をグラデーションカラーの大きな数字で強調する
                        Text("\(viewModel.score)")
                            .font(.system(size: 52, weight: .black, design: .rounded))
                            .foregroundStyle(LinearGradient(
                                colors: [scoreColor, DS.accent],
                                startPoint: .top, endPoint: .bottom
                            ))
                        // 「/ 10問」形式で総問題数を小さく添える
                        Text(String(format: String(localized: "quiz_result_total_count"), viewModel.totalCount))
                            .font(.system(size: 14, weight: .medium, design: .rounded))
                            .foregroundStyle(DS.muted)
                    }
                }
                .frame(width: 160, height: 160)
            }
            .padding(.vertical, 36)
            .padding(.horizontal, 32)
            .background(
                RoundedRectangle(cornerRadius: DS.cardRadius)
                    .fill(DS.card)
                    .shadow(color: .black.opacity(0.07), radius: 18, x: 0, y: 6)
            )
            .padding(.horizontal, 28)

            Spacer()

            // 新着シールバナー。獲得シールがある場合のみスプリングアニメーションで表示する。
            // ドラッグして盤面に置くか、ドラッグしなかった場合は「もう一度」タップ時に自動配置される
            if !newStickerEmojis.isEmpty {
                VStack(spacing: 8) {
                    // 獲得枚数に応じてメッセージを単数形・複数形で切り替える
                    Text("Got \(newStickerEmojis.count) Stickers!")
                        .font(.system(size: 15, weight: .black, design: .rounded))
                        .foregroundStyle(DS.primary)

                    HStack(spacing: 4) {
                        ForEach(Array(newStickerEmojis.enumerated()), id: \.offset) { idx, emoji in
                            // DraggablePendingStickerChip：ドラッグで盤面に配置できるシールチップ
                            // ドラッグ完了コールバックで配列から該当シールを削除する
                            DraggablePendingStickerChip(emoji: emoji) {
                                if let i = newStickerEmojis.firstIndex(of: emoji) {
                                    withAnimation(.easeIn(duration: 0.15)) {
                                        newStickerEmojis.remove(at: i)
                                        capturedPositions.removeValue(forKey: idx)
                                    }
                                }
                            }
                            // チップが画面上のどこに表示されているかをGeometryReaderで取得し、
                            // capturedPositionsに記録する。ドラッグしなかった場合の自動配置に使う
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
                .padding(.bottom, 8)
                // バナー出現時にスケール＋フェードで自然に現れるトランジションを設定する
                .transition(.scale(scale: 0.85).combined(with: .opacity))
            }

            // 「もう一度」ボタン。タップ前に残留シールを自動配置してからViewModelをリセットする
            Button {
                placeRemainingStickers()
                viewModel.restart()
            } label: {
                Label("quiz_play_again", systemImage: "arrow.counterclockwise")
                    .font(.system(size: 18, weight: .black, design: .rounded))
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
            .padding(.horizontal, 28)
            .padding(.bottom, 16)
        }
        .onAppear {
            // 画面表示時にStickerStoreから未配置のシールを取得してバナーに渡す。
            // pendingStickersが空のときはバナー自体を表示しない
            if !StickerStore.shared.pendingStickers.isEmpty {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.65)) {
                    newStickerEmojis = StickerStore.shared.pendingStickers
                }
            }
        }
        .onDisappear {
            // Viewが消える直前に残留シールを自動配置する。
            // 「もう一度」ボタン経由でも、別の操作で画面を離れた場合でもシールをロストしないための安全策
            placeRemainingStickers()
        }
    }

    /// ドラッグされなかった残りのシールを、バナー上の表示位置にそのまま配置する。
    // 座標はスクリーンサイズに対する比率（0.0〜1.0）に変換し、画面端への飛び出しを防ぐため
    // 8%〜92%の範囲にクランプしてからStickerStoreに渡す。
    private func placeRemainingStickers() {
        for (idx, emoji) in newStickerEmojis.enumerated() {
            if let pos = capturedPositions[idx] {
                // キャプチャ済みの座標があれば、その位置にシールを配置する
                StickerStore.shared.placePendingSticker(
                    emoji: emoji,
                    xRatio: max(0.08, min(0.92, pos.x / screenSize.width)),
                    yRatio: max(0.08, min(0.92, pos.y / screenSize.height))
                )
            } else {
                // 座標が取得できていない場合（稀なケース）はデフォルト位置に確定する
                StickerStore.shared.confirmPendingStickers()
            }
        }
        // 配置処理完了後にローカルの状態をクリアして重複配置を防ぐ
        newStickerEmojis = []
        capturedPositions = [:]
    }
}
