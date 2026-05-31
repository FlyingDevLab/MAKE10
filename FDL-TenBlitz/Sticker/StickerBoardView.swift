//
//  StickerBoardView.swift
//  FDL-TenBlitz
//
//  Created by 空飛ぶ研究室(FlyingDevLab) on 2026/03/21.
//
//  ゲーム画面の下部エリアに浮かぶ絵文字シール。
//  ドラッグで自由に動かせる。位置は StickerStore が永続化する。
//  7個以上でゴミ箱が解放され、ドラッグ&ドロップで削除できる。

// 【このファイルの役割】
// シールボード全体を管理するビュー群。StickerBoardView がルートで、
// 個別シールのドラッグ操作を DraggableStickerView、ゴミ箱 UI を TrashBinView に委譲する。

import SwiftUI

// MARK: - Sticker Board View
// MakeTenContentView の ZStack に重ねて使う全画面透明レイヤー。
// シール以外の領域はタッチを透過させる。

struct StickerBoardView: View {
    // シールの状態と永続化を一元管理するシングルトン
    private let store = StickerStore.shared

    // ゴミ箱サイズ定数
    // ゴミ箱アイコンの当たり判定および表示に使う固定サイズと余白
    private let trashSize:     CGFloat = 52
    private let trashTrailing: CGFloat = 16   // 画面右端からの距離
    private let trashBottom:   CGFloat = 52   // 画面下端からの距離

    // 現在ドラッグ中のシール ID（nil = 何もドラッグしていない）
    @State private var draggingID:        UUID?  = nil
    // ドラッグ中のシールがゴミ箱の上にあるか（ホバー状態のハイライト制御に使う）
    @State private var isOverTrash:       Bool   = false
    // 「全部削除」確認アラートの表示フラグ
    @State private var showDeleteAllAlert: Bool   = false
    // ゴミ箱の長押し中かどうか（アイコン拡大アニメに使う）
    @State private var isLongPressingTrash: Bool  = false

    var body: some View {
        GeometryReader { geo in
            // trashFrame は @State を持たず geo.size から毎回直接計算する。
            // これにより、シール削除アニメーション等でビューが再描画されても
            // SwiftUI のレイアウトエンジンに影響されずに位置が安定する。
            //
            // 【計算の意図】画面右下の固定位置にゴミ箱の CGRect を求める。
            // DraggableStickerView がドロップ先判定に使うため、
            // 毎フレーム最新の geo.size から算出して常に正確な座標を保つ。
            let trashFrame = CGRect(
                x: geo.size.width  - trashTrailing - trashSize,
                y: geo.size.height - trashBottom   - trashSize,
                width:  trashSize,
                height: trashSize
            )

            ZStack {
                // シール群
                // StickerStore の stickers 配列をそのまま ForEach に渡し、
                // 各シールを独立した DraggableStickerView として並べる。
                // bringToFront により z-order は配列順に反映される。
                ForEach(store.stickers) { sticker in
                    DraggableStickerView(
                        sticker:      sticker,
                        bounds:       geo.size,
                        trashFrame:   trashFrame,
                        draggingID:   $draggingID,
                        isOverTrash:  $isOverTrash
                    )
                }

                // ゴミ箱アイコン（7個以上で表示）
                // alignment+padding ではなく .position() で絶対配置することで
                // 他のビューのレイアウト変化（シール削除アニメ等）の影響を完全に遮断する。
                //
                // 【表示条件】isTrashUnlocked = シール7個以上のとき。
                // 長押しで全削除アラートを表示し、ドロップで個別削除のトリガーになる。
                if store.isTrashUnlocked {
                    TrashBinView(isOver: isOverTrash, isLongPressing: isLongPressingTrash)
                        // trashFrame の中心に絶対配置（レイアウト外の影響を受けない）
                        .position(x: trashFrame.midX, y: trashFrame.midY)
                        // 長押し確定時：バイブレーション → 長押しフラグを戻してアラート表示
                        .onLongPressGesture(minimumDuration: 0.7, maximumDistance: 30) {
                            SoundManager.shared.vibrate()
                            isLongPressingTrash = false
                            showDeleteAllAlert = true
                        } onPressingChanged: { pressing in
                            // 押下中はアイコンを拡大し、押し始めにバイブレーションで応答
                            withAnimation(.easeInOut(duration: 0.15)) {
                                isLongPressingTrash = pressing
                            }
                            if pressing { SoundManager.shared.vibrate() }
                        }
                        // 全削除の最終確認アラート
                        .alert("Delete All Stickers?", isPresented: $showDeleteAllAlert) {
                            Button("Delete All", role: .destructive) {
                                // アニメ付きで全シールを削除
                                withAnimation { StickerStore.shared.deleteAllStickers() }
                            }
                            Button("Cancel", role: .cancel) { }
                        } message: {
                            Text("All stickers on the board will be removed.")
                        }
                }
            }
        }
        // 座標空間名を付与し、DraggableStickerView が同一空間で座標を取得できるようにする
        .coordinateSpace(name: "stickerBoard")
    }
}

// MARK: - Draggable Sticker View

// 個々のシール1枚を表すビュー。ドラッグ操作・ゴミ箱ホバー判定・削除アニメを自己完結で処理する。
struct DraggableStickerView: View {
    // 表示するシールのデータモデル（絵文字・座標比率・ID）
    let sticker:     StickerStore.Sticker
    // 親ビューの描画サイズ（座標比率を実ピクセルに変換するために使う）
    let bounds:      CGSize
    // ゴミ箱の CGRect（ドロップ先判定に使う）
    let trashFrame:  CGRect
    // 複数シール間でドラッグ中の ID を共有するバインディング（z-order 制御用）
    @Binding var draggingID:  UUID?
    // ゴミ箱ホバー状態を親と共有し、ゴミ箱アイコンのハイライトに反映させる
    @Binding var isOverTrash: Bool

    // ドラッグ中の一時位置（nil = ドラッグ非中、保存済み座標を使う）
    @State private var livePosition: CGPoint? = nil
    // ドラッグ保持中フラグ（浮き上がりアニメの切り替えに使う）
    @State private var isHeld: Bool = false
    // ゴミ箱ドロップ予告フラグ（true のとき赤く縮んでいく）
    @State private var willDelete: Bool = false   // ゴミ箱ドロップ予告（赤く縮む）

    // このシールが現在ドラッグされているかを判定（影色やスケールの切り替えに使う）
    private var isMe: Bool { draggingID == sticker.id }

    // 表示に使う座標：ドラッグ中は livePosition、静止中は永続化座標から復元した storedPosition を使う
    private var displayPosition: CGPoint {
        livePosition ?? storedPosition
    }
    // xRatio / yRatio（0〜1）を実ピクセル座標に変換する。bounds が変わっても追従する。
    private var storedPosition: CGPoint {
        CGPoint(
            x: sticker.xRatio * bounds.width,
            y: sticker.yRatio * bounds.height
        )
    }

    var body: some View {
        Text(sticker.emoji)
            .font(.system(size: 36))
            // ゴミ箱ホバー時は縮小、ドラッグ中は拡大、静止時は等倍
            .scaleEffect(willDelete ? 0.5 : (isHeld ? 1.30 : 1.0))
            // ゴミ箱ホバー時は半透明にして「消えそう感」を演出
            .opacity(willDelete ? 0.4 : 1.0)
            // ドラッグ中だけ影を表示（静止中はフラットに見せる）
            // isOverTrash かつ自分がドラッグ中のとき赤い影でゴミ箱への投入を示唆
            .shadow(
                color: isHeld ? (isOverTrash && isMe ? .red.opacity(0.35) : .black.opacity(0.20)) : .clear,
                radius: 8, x: 0, y: 4
            )
            // isHeld・willDelete それぞれ独立したスプリングアニメを定義
            .animation(.spring(response: 0.22, dampingFraction: 0.55), value: isHeld)
            .animation(.spring(response: 0.20, dampingFraction: 0.60), value: willDelete)
            // displayPosition で絶対配置（ZStack 内で自由に動かせるようにする）
            .position(displayPosition)
            .gesture(
                // coordinateSpace を stickerBoard に揃えることで、
                // GeometryReader が返す trashFrame と同じ座標系で位置比較できる
                DragGesture(minimumDistance: 2, coordinateSpace: .named("stickerBoard"))
                    .onChanged { value in
                        // ドラッグ開始の初回のみ：バイブ・フラグ設定・z-order を最前面に
                        if !isHeld {
                            SoundManager.shared.vibrate()
                            isHeld     = true
                            draggingID = sticker.id
                            StickerStore.shared.bringToFront(id: sticker.id)
                        }
                        // クランプ済みの座標を livePosition に反映して追従表示
                        let pos = clamped(value.location)
                        livePosition = pos

                        // ゴミ箱ホバー判定
                        // ゴミ箱が解放済みかつ自分の位置が trashFrame に入ったら isOverTrash を ON
                        let over = StickerStore.shared.isTrashUnlocked && trashFrame.contains(pos)
                        // 状態が変化したときだけアニメ更新することで不要な再描画を抑える
                        if over != (isOverTrash && isMe) {
                            withAnimation(.easeInOut(duration: 0.15)) { isOverTrash = over }
                            // ゴミ箱に入った瞬間だけバイブレーションで触覚フィードバック
                            if over { SoundManager.shared.vibrate() }
                        }
                        willDelete = over
                    }
                    .onEnded { value in
                        let pos = clamped(value.location)
                        // ドロップ先がゴミ箱かどうかを最終判定
                        let overTrash = StickerStore.shared.isTrashUnlocked && trashFrame.contains(pos)

                        if overTrash {
                            // ゴミ箱ドロップ：縮小アニメを0.18秒走らせてから削除
                            // アニメ完了後に deleteSticker を呼ぶことで視覚的な消滅感を出す
                            withAnimation(.easeIn(duration: 0.18)) { willDelete = true }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                                StickerStore.shared.deleteSticker(id: sticker.id)
                            }
                        } else {
                            // 通常ドロップ：位置保存（updatePosition を先に呼んでから livePosition を nil に）
                            // updatePosition を先に呼ぶことで、livePosition をクリアした瞬間に
                            // storedPosition が最新値へ切り替わり、位置の一瞬のブレを防ぐ
                            StickerStore.shared.updatePosition(
                                id:     sticker.id,
                                xRatio: pos.x / bounds.width,
                                yRatio: pos.y / bounds.height
                            )
                            livePosition = nil
                        }

                        // ドラッグ終了後の共有状態をリセット
                        isHeld      = false
                        draggingID  = nil
                        isOverTrash = false
                        // overTrash=true の場合は willDelete=true のままにして
                        // 縮小アニメを完走させる（deleteSticker 後にビューが消える）
                        if !overTrash { willDelete = false }
                    }
            )
    }

    /// フッターゾーン（下部 約50pt）に入らないようにクランプ
    // シールがフッター UI に重ならないよう、ドラッグ座標を安全な範囲に制限する。
    // 上端・左右端にも余白を設け、完全に画面外へ出ないようにする。
    private func clamped(_ point: CGPoint) -> CGPoint {
        let footerHeight: CGFloat = 52
        return CGPoint(
            x: max(24, min(bounds.width  - 24, point.x)),
            y: max(80, min(bounds.height - footerHeight - 18, point.y))
        )
    }
}

// MARK: - Trash Bin View

// ゴミ箱アイコンを描画するビュー。ホバー状態・長押し状態に応じて色とスケールを変化させる。
// 実際の削除ロジックは持たず、見た目のフィードバックのみを担う。
struct TrashBinView: View {
    // ドラッグしているシールがゴミ箱の上にあるか（ホバーハイライト制御）
    let isOver: Bool
    // ゴミ箱を長押し中かどうか（全削除の予備動作として強調表示に使う）
    let isLongPressing: Bool

    var body: some View {
        ZStack {
            // 背景の丸：長押し > ホバー > 通常 の優先順位で色を変化させる
            Circle()
                .fill(isLongPressing ? DS.gaugeWarn.opacity(0.30)
                      : isOver       ? DS.gaugeWarn.opacity(0.15)
                      :                Color.black.opacity(0.05))
                .frame(width: 52, height: 52)

            // ゴミ箱アイコン：ホバー or 長押し時は fill バリアントに切り替え、警告色で強調する
            Image(systemName: isOver || isLongPressing ? "trash.fill" : "trash")
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(isOver || isLongPressing ? DS.gaugeWarn : DS.muted.opacity(0.55))
                // ホバーや長押しのタイミングで少し拡大し、操作可能であることを示す
                .scaleEffect(isLongPressing ? 1.25 : isOver ? 1.15 : 1.0)
        }
        // 長押し中はアイコン全体をさらに拡大してフィードバックを強める
        .scaleEffect(isLongPressing ? 1.12 : 1.0)
        // isOver と isLongPressing それぞれ独立したスプリングで滑らかに変化させる
        .animation(.spring(response: 0.25, dampingFraction: 0.6), value: isOver)
        .animation(.spring(response: 0.20, dampingFraction: 0.5), value: isLongPressing)
    }
}
