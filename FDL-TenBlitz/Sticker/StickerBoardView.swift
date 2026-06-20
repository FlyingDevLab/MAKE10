//
//  StickerBoardView.swift
//  FDL-TenBlitz
//
//  Created by 空飛ぶ研究室(FlyingDevLab) on 2026/03/21.
//
//  ゲーム画面の下部エリアに浮かぶ絵文字シール。
//  ドラッグで自由に動かせる。位置は StickerStore が永続化する。
//  stickers 配列の先頭 50 枚のみを表示する（51 枚目以降はストレージ画面で管理）。

// 【このファイルの役割】
// シールボード全体を管理するビュー群。StickerBoardView がルートで、
// 個別シールのドラッグ操作を DraggableStickerView に委譲する。
// ゴミ箱機能は廃止。シールの削除はストレージ画面から行う。

import SwiftUI

// MARK: - StickerBoardView
// MakeTenContentView の ZStack に重ねて使う全画面透明レイヤー。
// シール以外の領域はタッチを透過させる。

struct StickerBoardView: View {
    // シールの状態と永続化を一元管理するシングルトン
    private let store = StickerStore.shared

    // 現在ドラッグ中のシール ID（nil = 何もドラッグしていない）
    @State private var draggingID: UUID? = nil

    var body: some View {
        GeometryReader { geo in
            ZStack {
                // stickers の先頭 50 枚のみを表示する。
                // 51 枚目以降は配列に残るが描画しない（ストレージ画面で操作可能）。
                // bringToFront により z-order は配列順に反映される。
                ForEach(store.stickers.prefix(50)) { sticker in
                    DraggableStickerView(
                        sticker:    sticker,
                        bounds:     geo.size,
                        draggingID: $draggingID
                    )
                }
            }
        }
        // 座標空間名を付与し、DraggableStickerView が同一空間で座標を取得できるようにする
        .coordinateSpace(name: "stickerBoard")
    }
}

// MARK: - DraggableStickerView

// 個々のシール1枚を表すビュー。ドラッグ操作・位置保存を自己完結で処理する。
// ゴミ箱関連のロジックは廃止済み。
struct DraggableStickerView: View {
    // 表示するシールのデータモデル（絵文字・座標比率・ID）
    let sticker:    StickerStore.Sticker
    // 親ビューの描画サイズ（座標比率を実ピクセルに変換するために使う）
    let bounds:     CGSize
    // 複数シール間でドラッグ中の ID を共有するバインディング（z-order 制御用）
    @Binding var draggingID: UUID?

    // ドラッグ中の一時位置（nil = ドラッグ非中、保存済み座標を使う）
    @State private var livePosition: CGPoint? = nil
    // ドラッグ保持中フラグ（浮き上がりアニメの切り替えに使う）
    @State private var isHeld: Bool = false

    // このシールが現在ドラッグされているかを判定（影色やスケールの切り替えに使う）
    private var isMe: Bool { draggingID == sticker.id }

    // 表示に使う座標：ドラッグ中は livePosition、静止中は storedPosition を使う
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
            // ドラッグ中は拡大、静止時は等倍
            .scaleEffect(isHeld ? 1.30 : 1.0)
            // ドラッグ中だけ影を表示（静止中はフラットに見せる）
            .shadow(
                color: isHeld ? .black.opacity(0.20) : .clear,
                radius: 8, x: 0, y: 4
            )
            .animation(.spring(response: 0.22, dampingFraction: 0.55), value: isHeld)
            // displayPosition で絶対配置（ZStack 内で自由に動かせるようにする）
            .position(displayPosition)
            .gesture(
                // coordinateSpace を stickerBoard に揃えることで
                // GeometryReader の座標系と一致させる
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
                        livePosition = clamped(value.location)
                    }
                    .onEnded { value in
                        let pos = clamped(value.location)
                        // 位置保存（updatePosition を先に呼んでから livePosition を nil に）
                        // updatePosition を先に呼ぶことで、livePosition をクリアした瞬間に
                        // storedPosition が最新値へ切り替わり、位置の一瞬のブレを防ぐ
                        StickerStore.shared.updatePosition(
                            id:     sticker.id,
                            xRatio: pos.x / bounds.width,
                            yRatio: pos.y / bounds.height
                        )
                        livePosition = nil
                        isHeld       = false
                        draggingID   = nil
                    }
            )
    }

    /// フッターゾーン（下部 約50pt）に入らないようにクランプ。
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
