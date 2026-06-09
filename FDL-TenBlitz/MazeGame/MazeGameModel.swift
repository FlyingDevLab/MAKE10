//
//  MazeGameModel.swift
//  FDL-TenBlitz
//
//  Created by 空飛ぶ研究室(FlyingDevLab) on 2026/04/13.
//

// game.js (Cheese Quest) のゲームロジックを Swift に移植。
// CADisplayLink で 60fps ループを駆動し、@Observable でビューに通知する。
//
// 座標系: Canvas と同じく origin=左上, Y=下向き (0〜BASE=570)
// grid[row][col] : 0=壁, 1=通路

import Foundation
import CoreGraphics
import QuartzCore   // CADisplayLink

// MARK: - Supporting Types

struct Mouse {
    var x: CGFloat
    var y: CGFloat
    var vx: CGFloat = 0
    var vy: CGFloat = 0
    var kb: Int = 0  // ノックバックフレーム数
}

struct MazeShockwave {
    var active = false
    var r:    CGFloat = 0
    var cool: Int     = 0
    var cx:   CGFloat = 0
    var cy:   CGFloat = 0
}

struct Particle {
    var x: CGFloat; var y: CGFloat
    var vx: CGFloat; var vy: CGFloat
    var life: Int; var maxLife: Int
}

/// 迷路内に配置される収集チーズ1個分のデータ
struct CheeseItem {
    var x: CGFloat
    var y: CGFloat
    var collected: Bool = false
}

// MARK: - MazeGameModel

@Observable
final class MazeGameModel: NSObject {

    // ── Constants ─────────────────────────────────────────────
    let BASE: CGFloat = 570         // 論理キャンバスサイズ
    let MC   = 6                    // セル数（片辺）
    let GW   = 19                   // グリッド幅 = MC*3+1
    let MOUSE_SPD: CGFloat = 1.05   // ネズミ移動速度(px/frame)
    let SW_EXPAND: CGFloat = 7      // 衝撃波拡張速度
    let SW_COOL   = 180             // 衝撃波クールダウン(frames)
    let DMG_COOL  = 60              // ダメージ無敵(frames)
    let MOVE_STEPS = 4              // slideMove のサブステップ数

    var T: CGFloat { BASE / CGFloat(GW) }   // タイルサイズ
    var CHEESE_R: CGFloat { T * 0.44 }
    var MOUSE_R:  CGFloat { T * 0.33 }

    func swRangeByHp(_ hp: Int) -> CGFloat {
        switch hp {
        case 3: return T * 5.0
        case 2: return T * 6.5
        default:return T * 8.0
        }
    }

    // ── Game State ────────────────────────────────────────────
    enum GameState { case title, playing, delivered, finished }
    var gameState:     GameState = .title
    var score          = 0          // 総チーズ回収数（表示用）
    var stage          = 0          // ステージ数（難易度計算専用・非表示）
    var isNewRecord    = false
    var deliveredTimer = 0

    /// 歴代最高スコア。ScoreBoard 経由で読み取る。
    var highScore: Int { ScoreBoard.highScore(for: UDKey.mazeHighScore) }

    // ── Maze ──────────────────────────────────────────────────
    var grid: [[Int]] = []          // [row][col], 0=壁 1=通路

    // ── Player（白ネズミ）────────────────────────────────────
    var cheeseX:     CGFloat = 0    // プレイヤーX座標（論理）
    var cheeseY:     CGFloat = 0    // プレイヤーY座標（論理）
    var playerAngle: CGFloat = 0    // 描画向き（ラジアン）
    var cheeseHp:    Int     = 3
    var cheeseFlash: Int     = 0    // ダメージ点滅カウンタ
    var cheeseDmgCool: Int  = 0    // 無敵フレーム

    // ── 収集チーズ（3コーナー配置）──────────────────────────
    var cheeses: [CheeseItem] = []

    // ── Enemies / Effects ─────────────────────────────────────
    var mice:      [Mouse]      = []
    var particles: [Particle]   = []
    var shockwave: MazeShockwave = MazeShockwave()

    // ── Spawn timer ───────────────────────────────────────────
    var spawnTimer = 0

    // ── Display Link ─────────────────────────────────────────
    private var displayLink: CADisplayLink?

    // ── Callbacks ─────────────────────────────────────────────
    var onGameOver: (() -> Void)?

    // MARK: - Difficulty

    func getDifficulty() -> (maxMice: Int, spawnInt: Int) {
        let maxMice  = max(2, stage * 2)
        let spawnInt = stage >= 6 ? 120 : stage >= 4 ? 150 : stage >= 2 ? 180 : 210
        return (maxMice, spawnInt)
    }

    // MARK: - Game Control

    func startGame() {
        score      = 0
        stage      = 0
        cheeseHp   = 3
        isNewRecord = false
        startStage()
        startLoop()
    }

    func startStage() {
        stage += 1
        buildMaze()
        // プレイヤーは左上コーナーのセル(0,0)中心にスタート
        cheeseX = T * 1.5; cheeseY = T * 1.5
        playerAngle  = 0
        cheeseFlash  = 0; cheeseDmgCool = 0
        // 残り3コーナーにチーズを配置
        // セル(cx,cy) の中心座標 = ((cx*3+1) + 0.5) * T = (cx*3 + 1.5) * T
        cheeses = [
            CheeseItem(x: T * 16.5, y: T * 1.5),   // 右上コーナー (5,0)
            CheeseItem(x: T * 1.5,  y: T * 16.5),  // 左下コーナー (0,5)
            CheeseItem(x: T * 16.5, y: T * 16.5),  // 右下コーナー (5,5)
        ]
        mice         = []; particles = []
        shockwave    = MazeShockwave()
        let (_, si)  = getDifficulty()
        spawnTimer   = si
        deliveredTimer = 0
        gameState    = .playing
    }

    func returnToTitle() {
        stopLoop()
        gameState = .title
    }

    // MARK: - Game Loop

    private func startLoop() {
        stopLoop()
        displayLink = CADisplayLink(target: self, selector: #selector(tick))
        displayLink?.add(to: .main, forMode: .default)
    }

    func stopLoop() {
        displayLink?.invalidate()
        displayLink = nil
    }

    @objc private func tick() {
        switch gameState {
        case .playing:   updatePlaying()
        case .delivered: updateDelivered()
        default: break
        }
    }

    // MARK: - Update

    private func updatePlaying() {
        if cheeseFlash > 0   { cheeseFlash -= 1 }
        if cheeseDmgCool > 0 { cheeseDmgCool -= 1 }

        // スポーン
        spawnTimer -= 1
        if spawnTimer <= 0 {
            spawnMouse()
            let (_, si) = getDifficulty()
            spawnTimer = si
        }

        updateMice()
        updateShockwave()
        updateParticles()

        // チーズ回収判定：プレイヤーが未回収チーズに重なったら取得
        for i in 0..<cheeses.count {
            guard !cheeses[i].collected else { continue }
            let dx = cheeseX - cheeses[i].x, dy = cheeseY - cheeses[i].y
            if sqrt(dx*dx + dy*dy) < CHEESE_R * 1.6 {
                cheeses[i].collected = true
                score += 1
                spawnParticles(cheeses[i].x, cheeses[i].y)
                SoundManager.shared.vibrate()
            }
        }

        // 全チーズ回収でステージクリア
        if cheeses.allSatisfy({ $0.collected }) {
            deliveredTimer = 110
            gameState = .delivered
        }
    }

    private func updateDelivered() {
        updateParticles()
        deliveredTimer -= 1
        if deliveredTimer <= 0 { startStage() }
    }

    // MARK: - Maze Generation (Recursive Backtracker)

    private func buildMaze() {
        grid = Array(repeating: Array(repeating: 0, count: GW), count: GW)
        var visited = Array(repeating: Array(repeating: false, count: MC), count: MC)

        func openCell(_ cx: Int, _ cy: Int) {
            let tx = cx * 3 + 1, ty = cy * 3 + 1
            grid[ty][tx]     = 1; grid[ty][tx + 1]     = 1
            grid[ty + 1][tx] = 1; grid[ty + 1][tx + 1] = 1
        }

        func openWall(_ cx: Int, _ cy: Int, _ nx: Int, _ ny: Int) {
            let tx = cx * 3 + 1, ty = cy * 3 + 1
            let dx = nx - cx, dy = ny - cy
            if      dx ==  1 { grid[ty][cx*3+3] = 1; grid[ty+1][cx*3+3] = 1 }
            else if dx == -1 { grid[ty][cx*3]   = 1; grid[ty+1][cx*3]   = 1 }
            else if dy ==  1 { grid[cy*3+3][tx] = 1; grid[cy*3+3][tx+1] = 1 }
            else if dy == -1 { grid[cy*3][tx]   = 1; grid[cy*3][tx+1]   = 1 }
        }

        func dfs(_ cx: Int, _ cy: Int) {
            visited[cy][cx] = true
            openCell(cx, cy)
            let dirs = [(-1, 0), (1, 0), (0, -1), (0, 1)]
                .shuffled()
            for (dx, dy) in dirs {
                let nx = cx + dx, ny = cy + dy
                guard nx >= 0, nx < MC, ny >= 0, ny < MC, !visited[ny][nx] else { continue }
                openWall(cx, cy, nx, ny)
                dfs(nx, ny)
            }
        }
        dfs(0, 0)
    }

    // MARK: - Collision

    func hitsWall(_ px: CGFloat, _ py: CGFloat, _ r: CGFloat) -> Bool {
        let x0 = max(0, Int((px - r) / T))
        let x1 = min(GW - 1, Int((px + r) / T))
        let y0 = max(0, Int((py - r) / T))
        let y1 = min(GW - 1, Int((py + r) / T))
        for ty in y0...y1 {
            for tx in x0...x1 {
                guard grid[ty][tx] == 0 else { continue }
                let nearX = max(CGFloat(tx) * T, min(px, CGFloat(tx + 1) * T))
                let nearY = max(CGFloat(ty) * T, min(py, CGFloat(ty + 1) * T))
                if (px - nearX) * (px - nearX) + (py - nearY) * (py - nearY) < r * r { return true }
            }
        }
        return false
    }

    private func pushOut(_ px: CGFloat, _ py: CGFloat, _ r: CGFloat) -> CGPoint {
        let x0 = max(0, Int((px - r) / T))
        let x1 = min(GW - 1, Int((px + r) / T))
        let y0 = max(0, Int((py - r) / T))
        let y1 = min(GW - 1, Int((py + r) / T))
        var ox: CGFloat = 0, oy: CGFloat = 0
        for ty in y0...y1 {
            for tx in x0...x1 {
                guard grid[ty][tx] == 0 else { continue }
                let nearX = max(CGFloat(tx) * T, min(px, CGFloat(tx + 1) * T))
                let nearY = max(CGFloat(ty) * T, min(py, CGFloat(ty + 1) * T))
                let dSq = (px - nearX) * (px - nearX) + (py - nearY) * (py - nearY)
                if dSq < r * r && dSq > 0 {
                    let d = sqrt(dSq)
                    ox += (px - nearX) / d * (r - d)
                    oy += (py - nearY) / d * (r - d)
                } else if dSq == 0 { ox += r }
            }
        }
        return CGPoint(x: px + ox, y: py + oy)
    }

    func slideMove(_ ox: CGFloat, _ oy: CGFloat, _ totalDx: CGFloat, _ totalDy: CGFloat, _ r: CGFloat) -> CGPoint {
        var cx = ox, cy = oy
        let sx = totalDx / CGFloat(MOVE_STEPS)
        let sy = totalDy / CGFloat(MOVE_STEPS)
        for _ in 0..<MOVE_STEPS {
            let nx = cx + sx, ny = cy + sy
            if      !hitsWall(nx, ny, r) { cx = nx; cy = ny }
            else if !hitsWall(nx, cy, r) { cx = nx }
            else if !hitsWall(cx, ny, r) { cy = ny }
            let po = pushOut(cx, cy, r)
            cx = po.x; cy = po.y
        }
        return CGPoint(x: cx, y: cy)
    }

    // MARK: - Input

    /// ドラッグのデルタ（論理座標）をプレイヤー移動に適用し、向き角度を更新する
    func moveCheese(dx: CGFloat, dy: CGFloat) {
        guard gameState == .playing else { return }
        if abs(dx) > 0.1 || abs(dy) > 0.1 {
            playerAngle = atan2(dy, dx)
        }
        let moved = slideMove(cheeseX, cheeseY, dx, dy, CHEESE_R)
        cheeseX = moved.x; cheeseY = moved.y
    }

    /// タップ位置（論理座標）に衝撃波を発射する
    func fireShockwave(at logicalPos: CGPoint) {
        guard gameState == .playing, shockwave.cool == 0 else { return }
        let swMaxR = swRangeByHp(cheeseHp)
        let killR  = swMaxR * 0.55
        shockwave  = MazeShockwave(active: true, r: 5, cool: SW_COOL,
                                    cx: logicalPos.x, cy: logicalPos.y)
        SoundManager.shared.vibrate()

        for i in (0..<mice.count).reversed() {
            let m = mice[i]
            let d = hypot(m.x - logicalPos.x, m.y - logicalPos.y)
            guard d <= swMaxR else { continue }
            if d < killR {
                spawnParticles(m.x, m.y)
                mice.remove(at: i)
            } else {
                let angle = atan2(m.y - logicalPos.y, m.x - logicalPos.x)
                let force = (1 - d / swMaxR) * 14
                mice[i].vx = cos(angle) * force
                mice[i].vy = sin(angle) * force
                mice[i].kb = 22
            }
        }
    }

    // MARK: - Mice

    private func spawnMouse() {
        let (maxMice, _) = getDifficulty()
        guard mice.count < maxMice else { return }
        for _ in 0..<200 {
            let tx = Int.random(in: 0..<GW)
            let ty = Int.random(in: 0..<GW)
            guard grid[ty][tx] == 1 else { continue }
            let mx = (CGFloat(tx) + 0.5) * T
            let my = (CGFloat(ty) + 0.5) * T
            guard hypot(mx - cheeseX, my - cheeseY) >= T * 5 else { continue }
            mice.append(Mouse(x: mx, y: my))
            break
        }
    }

    private func updateMice() {
        for i in (0..<mice.count).reversed() {
            if mice[i].kb > 0 {
                let moved = slideMove(mice[i].x, mice[i].y, mice[i].vx, mice[i].vy, MOUSE_R)
                mice[i].x = moved.x; mice[i].y = moved.y
                mice[i].vx *= 0.82; mice[i].vy *= 0.82
                mice[i].kb -= 1
            } else {
                let dx = cheeseX - mice[i].x, dy = cheeseY - mice[i].y
                let jitter = CGFloat.random(in: -0.5...0.5)
                let angle  = atan2(dy, dx) + jitter
                let vx     = cos(angle) * MOUSE_SPD
                let vy     = sin(angle) * MOUSE_SPD
                let moved  = slideMove(mice[i].x, mice[i].y, vx, vy, MOUSE_R)
                mice[i].x = moved.x; mice[i].y = moved.y
                mice[i].vx = vx; mice[i].vy = vy
            }

            // ダメージ判定
            let dist = hypot(mice[i].x - cheeseX, mice[i].y - cheeseY)
            if dist < CHEESE_R + MOUSE_R && cheeseDmgCool == 0 {
                cheeseHp    -= 1
                cheeseFlash  = 30
                cheeseDmgCool = DMG_COOL
                SoundManager.shared.vibrate()
                if cheeseHp <= 0 {
                    gameState = .finished
                    triggerGameOver()
                }
            }
        }
    }

    // MARK: - Shockwave

    private func updateShockwave() {
        if shockwave.cool > 0 { shockwave.cool -= 1 }
        guard shockwave.active else { return }
        shockwave.r += SW_EXPAND
        if shockwave.r >= swRangeByHp(cheeseHp) { shockwave.active = false }
    }

    // MARK: - Particles

    private func spawnParticles(_ x: CGFloat, _ y: CGFloat) {
        for i in 0..<8 {
            let angle = CGFloat(i) / 8 * .pi * 2
            let speed = CGFloat.random(in: 2...5)
            particles.append(Particle(
                x: x, y: y,
                vx: cos(angle) * speed, vy: sin(angle) * speed,
                life: 28, maxLife: 28
            ))
        }
    }

    private func updateParticles() {
        for i in (0..<particles.count).reversed() {
            particles[i].x += particles[i].vx
            particles[i].y += particles[i].vy
            particles[i].vx *= 0.88; particles[i].vy *= 0.88
            particles[i].life -= 1
            if particles[i].life <= 0 { particles.remove(at: i) }
        }
    }

    // MARK: - Game Over

    private func triggerGameOver() {
        stopLoop()
        // 新記録なら ScoreBoard が保存し true を返す
        isNewRecord = ScoreBoard.saveIfBetter(score: score, for: UDKey.mazeHighScore)
    }
}
