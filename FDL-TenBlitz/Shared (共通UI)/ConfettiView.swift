//
//  ConfettiView.swift
//  FDL-TenBlitz
//
//  Created by 空飛ぶ研究室(FlyingDevLab) on 2026/03/08.
//
//  紙吹雪エフェクト。結果画面で好成績時に表示する。

// 物理ベースの紙吹雪アニメーションをSwiftUI Canvasで実現するView群。
// 粒子の生成・移動・消滅をタイマー駆動で更新し、画面左右下部から噴き上げる演出を行う。

import SwiftUI
import Combine

// MARK: - Confetti
// isSpecial = true（100問以上）のときは金・銀・白の特別カラーで粒子数も多い。

// 紙吹雪の粒子1個分のデータモデル。
// Canvas上での描画位置・速度・色・透明度を保持し、フレームごとに更新される。
struct ConfettiParticle: Identifiable {
    let id = UUID()
    var x:       CGFloat  // 粒子の現在X座標
    var y:       CGFloat  // 粒子の現在Y座標
    var color:   Color    // 粒子の色（通常 or 特別カラー）
    var vx:      CGFloat  // X方向の速度（正＝右、負＝左）
    var vy:      CGFloat  // Y方向の速度（負＝上向き、重力で徐々に増加）
    var opacity: Double = 1.0  // 透明度。毎フレーム減少し、0以下になると粒子を削除する
}

struct ConfettiView: View {
    // 呼び出し元から渡される。trueのとき金・銀・白の特別演出になる
    let isSpecial: Bool

    // 現在画面上に存在する全粒子のリスト。フレームごとに状態が更新される
    @State private var particles:        [ConfettiParticle] = []

    // タイマーの購読を保持する。onDisappear時にキャンセルしてメモリリークを防ぐ
    @State private var timerCancellable: AnyCancellable?

    var body: some View {
        GeometryReader { geo in
            // 大量の粒子を効率よく描画するためにCanvasを使用。
            // 通常のViewツリーでは粒子数が多いときのパフォーマンスに難があるため。
            Canvas { context, _ in
                for p in particles {
                    var ctx = context
                    ctx.opacity = p.opacity
                    // isSpecialのときは粒子をやや大きく描画して存在感を強調する
                    let size: CGFloat = isSpecial ? 12 : 10
                    ctx.fill(
                        Path(ellipseIn: CGRect(
                            x: p.x, y: p.y,
                            width:  size,
                            height: size
                        )),
                        with: .color(p.color)
                    )
                }
            }
            .onAppear {
                // 表示と同時に粒子を生成し、アニメーションループを開始する
                spawnParticles(in: geo.size)
                // 50fps（0.02秒間隔）でフレーム更新。メインスレッドでUIを安全に操作する
                timerCancellable = Timer.publish(every: 0.02, on: .main, in: .common)
                    .autoconnect()
                    .sink { _ in updateParticles() }
            }
            .onDisappear {
                // Viewが消えたらタイマーを必ず止めて、バックグラウンドでの無駄な更新を防ぐ
                timerCancellable?.cancel()
                timerCancellable = nil
            }
        }
    }

    // 画面左端・右端の下部から、粒子を左右対称に噴き上げる形で初期配置する。
    // isSpecialに応じて色パレットと総粒子数を切り替える。
    private func spawnParticles(in size: CGSize) {
        // isSpecialなら金・銀・白のリッチなカラーで、通常は虹色の7色
        let colors: [Color] = isSpecial
            ? [Color(red: 1.0, green: 0.84, blue: 0.0), .white,
               Color(red: 0.75, green: 0.75, blue: 0.75)]
            : [.red, .blue, .green, .yellow, .pink, .purple, .orange]

        // isSpecialは通常の2.5倍の粒子数で豪華な演出にする
        let count = isSpecial ? 150 : 60

        for _ in 0..<count {
            // 左端から右上方向にランダムな速度で噴き上げる粒子
            particles.append(ConfettiParticle(
                x: 0,          y: size.height * 0.8, color: colors.randomElement()!,
                vx: .random(in: 2...15),   vy: .random(in: -28...(-10))
            ))
            // 右端から左上方向にランダムな速度で噴き上げる粒子（左右対称の演出）
            particles.append(ConfettiParticle(
                x: size.width, y: size.height * 0.8, color: colors.randomElement()!,
                vx: .random(in: -15...(-2)), vy: .random(in: -28...(-10))
            ))
        }
    }

    // 毎フレーム（約50fps）呼ばれ、全粒子の位置・速度・透明度を更新する。
    // 透明度が0以下になった粒子は配列から除去することで、使い終わった粒子を自動解放する。
    private func updateParticles() {
        for i in 0..<particles.count {
            particles[i].x       += particles[i].vx
            particles[i].y       += particles[i].vy
            particles[i].vy      += 0.5    // 重力加速度
            particles[i].opacity -= 0.008  // 徐々に透明化
        }
        // 完全に透明になった粒子を削除してメモリを解放する
        particles.removeAll { $0.opacity <= 0 }
    }
}
