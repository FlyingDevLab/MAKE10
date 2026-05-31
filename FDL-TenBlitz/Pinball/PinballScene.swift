//
//  PinballScene.swift
//  FDL-TenBlitz
//
//  Created by 空飛ぶ研究室(FlyingDevLab) on 2026/04/13.
//

// game.js の物理エンジン・描画システムを SpriteKit で再実装。
// 座標系: Canvas は Y 下向き(origin左上)、SpriteKit は Y 上向き(origin左下)。
// 変換: sk_y = CH - canvas_y  (CH = 700)
//
// 主な対応関係:
//   requestAnimationFrame → update(_:)
//   resolveSegment/Circle/Rect → SKPhysicsBody + SKPhysicsContactDelegate
//   localStorage → UserDefaults (PinballViewModel で管理)
//   Canvas drawXxx → SKShapeNode

import SpriteKit
import UIKit

// MARK: - Physics Categories

private struct Cat {
    static let ball:    UInt32 = 1 << 0
    static let wall:    UInt32 = 1 << 1
    static let bumper:  UInt32 = 1 << 2
    static let sling:   UInt32 = 1 << 3
    static let target:  UInt32 = 1 << 4
    static let flipper: UInt32 = 1 << 5
}

// MARK: - ⚙️ 調整パラメータ（ここだけ触ればOK）
//
// ┌─────────────────────────────────────────────────────────────┐
// │  このブロックに全ての数値定数をまとめています。             │
// │  ゲームの挙動を変えたいときはここだけ編集してください。     │
// └─────────────────────────────────────────────────────────────┘

private enum Tuning {

    // ── 物理ワールド ──────────────────────────────────────────
    /// 重力加速度 (px/s²)。マイナス=下向き。大きいほど速く落ちる。
    /// launch.vy とセットで調整すること（目安: vy ≈ gravity の 2.5〜3倍）
    static let gravity:         CGFloat = -8

    /// 物理演算速度倍率。1.0=通常 / 2.0=2倍速（全体的に速くなる）
    static let worldSpeed:      CGFloat = 1.0

    // ── ボール ────────────────────────────────────────────────
    /// ボール反発係数 (0=吸収 / 1=完全弾性)
    static let ballRestitution: CGFloat = 0.59
    /// ボール摩擦 (0=スルスル / 1=ガリガリ)
    static let ballFriction:    CGFloat = 0.1
    /// 空気抵抗 (0=減速なし。大きくするとふわっと遅くなる)
    static let ballDamping:     CGFloat = 0.05

    // ── 発射初速 ──────────────────────────────────────────────
    /// 横方向の打ち出し速度 (px/s)。大きいほど斜めに飛ぶ
    static let launchVX:        CGFloat = 5
    /// 上方向の打ち出し速度 (px/s)。gravity とセットで調整
    static let launchVY:        CGFloat = 10

    // ── 壁・アーチ ────────────────────────────────────────────
    /// 壁/アーチの反発係数 (0=吸収 / 1=完全弾性)
    static let wallRestitution: CGFloat = 0.9
    /// 壁/アーチの摩擦
    static let wallFriction:    CGFloat = 0.1

    // ── バンパー ──────────────────────────────────────────────
    /// バンパーの反発係数 (1=エネルギー維持 / 1超=加速)
    static let bumperRestitution: CGFloat = 1.2
    /// バンパー当たり後の最低保証速度 (px/s)。小さいと緩やかに弾く
    static let bumperMinSpeed:    CGFloat = 500
    /// バンパー発光の継続時間 (秒)
    static let bumperFlashDur:    TimeInterval = 0.2

    // ── スリングショット ──────────────────────────────────────
    /// スリング反発係数 (1超=エネルギー増加)
    static let slingRestitution:  CGFloat = 1.1
    /// スリング追加インパルス (px/s)。大きいほど激しく弾く
    static let slingImpulse:      CGFloat = 540

    // ── ターゲット ────────────────────────────────────────────
    /// ターゲットの反発係数
    static let targetRestitution: CGFloat = 0.8
    /// ターゲットの摩擦
    static let targetFriction:    CGFloat = 0.1
    /// ターゲット消灯→点灯までの秒数。短いほど連打しやすい
    static let targetRestoreSec:  TimeInterval = 4.0
    /// 2倍スコアタイムの継続秒数
        static let doubleScoreDuration: TimeInterval = 10.0
    // ── フリッパー ────────────────────────────────────────────
    /// フリッパーの反発係数 (低めが自然)
    static let flipperRestitution: CGFloat = 0.4
    /// フリッパーの摩擦
    static let flipperFriction:    CGFloat = 0.2
    /// フリッパー上げ速度 (rad/s)。大きいほど素早い
    static let flipperRaiseSpeed:  CGFloat = 14
    /// フリッパー下げ速度 (rad/s)
    static let flipperLowerSpeed:  CGFloat = 7
    /// 左フリッパー休止角 (度 → ラジアン変換済み)
    static let lRestAngle:  CGFloat = -.pi * 30 / 180
    /// 左フリッパー作動角
    static let lActiveAngle: CGFloat = .pi * 25 / 180
    /// 右フリッパー休止角
    static let rRestAngle:  CGFloat = .pi * 30 / 180
    /// 右フリッパー作動角
    static let rActiveAngle: CGFloat = -.pi * 25 / 180

    // ── スラップブースト（フリッパー打ち出し強化） ────────────
    /// フリッパー上昇中ヒット時の横方向追加速度 (px/s)
    static let slapBoostDX: CGFloat = 150
    /// フリッパー上昇中ヒット時の上方向追加速度 (px/s)
    static let slapBoostDY: CGFloat = 900

    // ── 速度上限 ──────────────────────────────────────────────
    /// ボール最高速度 (px/s)。バンパー連打での無限加速を防止
    static let maxSpeed:    CGFloat = 1200
}

// MARK: - PinballScene

final class PinballScene: SKScene, SKPhysicsContactDelegate {

    // ── フィールド定数（レイアウト用。物理パラメータは Tuning へ） ──
    private let CW: CGFloat = 390          // シーン幅 (px)
    private let CH: CGFloat = 700          // シーン高さ (px)
    private let BR: CGFloat = 13           // ボール半径 (px) ← 大きくすると当たりやすい
    private let FL: CGFloat = 80           // フリッパー長さ (px) ← 長くすると打ちやすい
    private let FW: CGFloat = 10           // フリッパー描画太さ (px)
    private let FY: CGFloat = 80           // フリッパーピボット Y座標 (SK: 700 - 620 = 80)
    private let LPX: CGFloat = 95          // 左フリッパーピボット X
    private let RPX: CGFloat = 295         // 右フリッパーピボット X
    private let BUMP_R: CGFloat = 23       // バンパー半径 (px) ← 大きくすると当たりやすい
    private let TW: CGFloat = 52           // ターゲット幅 (px)
    private let TH: CGFloat = 18           // ターゲット高さ (px)
    private let MAX_BALLS = 3              // 残機数

    // ── フリッパー角度（Tuning から参照） ────────────────────
    private var lRestAngle:   CGFloat { Tuning.lRestAngle   }
    private var lActiveAngle: CGFloat { Tuning.lActiveAngle }
    private var rRestAngle:   CGFloat { Tuning.rRestAngle   }
    private var rActiveAngle: CGFloat { Tuning.rActiveAngle }
    private var raiseSpeed:   CGFloat { Tuning.flipperRaiseSpeed }
    private var lowerSpeed:   CGFloat { Tuning.flipperLowerSpeed }

    // ── Nodes ─────────────────────────────────────────────────
    private var lFlipNode = SKNode()
    private var rFlipNode = SKNode()
    private var ballNode: SKShapeNode?
    private var bumperNodes: [SKShapeNode] = []
    private var targetNodes: [SKShapeNode] = []
    private var scoreLabel: SKLabelNode!
    private var ballsLabel:  SKLabelNode!
    private var doubleScoreLabel: SKLabelNode!

    // ── State ─────────────────────────────────────────────────
    private var internalScore = 0
    private var lastUpdateTime: TimeInterval = 0
    var lFlipRaised = false
    var rFlipRaised = false
    private var isLFlipRaising = false
    private var isRFlipRaising = false
    private var ballDrainPending = false  // 二重ドレイン防止

    // ── セットアップ済みフラグ（didMove の二重呼び出し対策） ──
    // SKView に同一シーンが再提示されると didMove が再度呼ばれ、
    // targetNodes/bumperNodes に重複 append されてクラッシュする。
    // このフラグで初回のみ実行するよう保護する。
    private var isSetupDone = false

    // ターゲット: 4つ (left/center/right + center-hi)
    private struct TargetState { var active = true; var restore: TimeInterval = Tuning.targetRestoreSec }
    private var targetStates: [TargetState] = Array(repeating: TargetState(), count: 4)
    private let targetPoints = [1000, 1000, 1000, 10000]

    // バンパー: 3つ（flash タイマー）
    private var bumperFlash: [TimeInterval] = [0, 0, 0]
    // 2倍スコアタイム残り秒数（0以下 = 無効）
        private var doubleScoreTimer: TimeInterval = 0
    // スコアポップアップ
    private struct Popup { var node: SKLabelNode; var vy: CGFloat = 80; var alpha: CGFloat = 1.0 }
    private var popups: [Popup] = []

    // ── Callbacks ─────────────────────────────────────────────
    var onScoreChanged: ((Int) -> Void)?
    var onBallDrained:  (() -> Void)?

    // ── Setup ─────────────────────────────────────────────────

    override func didMove(to view: SKView) {
        // 二重呼び出し対策: 初回のみセットアップを実行する
        guard !isSetupDone else { return }
        isSetupDone = true

        backgroundColor = SKColor(red: 0.027, green: 0.027, blue: 0.078, alpha: 1)

        // ── 重力 ─────────────────────────────────────────────
        // SpriteKit は Y 上向き正。dy がマイナス = 下向き重力。
        // 大きくするとボールが速く落ちる。launch の dy もセットで調整すること。
        physicsWorld.gravity = CGVector(dx: 0, dy: Tuning.gravity)
        physicsWorld.contactDelegate = self
        physicsWorld.speed = Tuning.worldSpeed

        setupWalls()
        setupArch()
        setupSlingshots()
        setupBumpers()
        setupTargets()
        setupFlippers()
        setupHUD()
        launchBall()
    }

    // MARK: - Wall Setup

    private func setupWalls() {
        // 左右の壁（画面外まで延長してすり抜け防止）
        addWallEdge(from: CGPoint(x: 0,   y: -200), to: CGPoint(x: 0,   y: 800))
        addWallEdge(from: CGPoint(x: CW,  y: -200), to: CGPoint(x: CW,  y: 800))

        // ガイドウォール（フリッパー上部の傾斜壁）
        // canvas: LGY = FY_canvas - LPX * tan(30°) = 620 - 95 * 0.5774 = 565.15
        // SK: 700 - 565.15 = 134.85
        let gSlope = tan(30.0 * .pi / 180.0)  // ≈ 0.5774
        let lgy: CGFloat = FY + LPX * gSlope  // SK: 80 + 95*0.5774 ≈ 134.85
        let rgy: CGFloat = FY + (CW - RPX) * gSlope

        addWallEdge(from: CGPoint(x: 0,   y: lgy),  to: CGPoint(x: LPX, y: FY), lineWidth: 14)
        addWallEdge(from: CGPoint(x: RPX, y: FY),   to: CGPoint(x: CW,  y: rgy), lineWidth: 14)

        // スリングウォール（スリングショット周囲の補助壁）
        // canvas sc(0.14, 0.22) = (54.6, 483.6) → SK (54.6, 216.4)
        // canvas sc(0.14, 0.14) = (54.6, 533.2) → SK (54.6, 166.8)
        // canvas sc(0.24, 0.14) = (93.6, 533.2) → SK (93.6, 166.8)
        addWallEdge(from: CGPoint(x: 54.6,  y: 216.4), to: CGPoint(x: 54.6, y: 166.8))
        addWallEdge(from: CGPoint(x: 54.6,  y: 166.8), to: CGPoint(x: 93.6, y: 166.8))
        addWallEdge(from: CGPoint(x: 335.4, y: 216.4), to: CGPoint(x: 335.4, y: 166.8))
        addWallEdge(from: CGPoint(x: 296.4, y: 166.8), to: CGPoint(x: 335.4, y: 166.8))
    }

    private func addWallEdge(from a: CGPoint, to b: CGPoint, lineWidth: CGFloat = 5) {
        let node = SKNode()
        let body = SKPhysicsBody(edgeFrom: a, to: b)
        body.categoryBitMask    = Cat.wall
        body.collisionBitMask   = Cat.ball
        body.restitution        = Tuning.wallRestitution
        body.friction           = Tuning.wallFriction
        node.physicsBody = body
        addChild(node)

        // 壁の描画
        let shape = SKShapeNode()
        let path = CGMutablePath()
        path.move(to: a); path.addLine(to: b)
        shape.path        = path
        shape.strokeColor = SKColor(white: 0.75, alpha: 0.9)
        shape.lineWidth   = lineWidth
        addChild(shape)
    }

    // MARK: - Arch Setup

    private func setupArch() {
        // アーチ(上部半円境界): canvas ARCH_CX=195, ARCH_CY=230, ARCH_R=210
        // SK: center=(195, 470), radius=210
        // SK point: (195 - 210*cos(a), 470 + 210*sin(a)) for a in 0...π
        let archCX: CGFloat = 195, archCY: CGFloat = 470, archR: CGFloat = 210
        let n = 16
        var pts = [CGPoint]()
        for i in 0...n {
            let a = CGFloat.pi * CGFloat(i) / CGFloat(n)
            pts.append(CGPoint(x: archCX - archR * cos(a), y: archCY + archR * sin(a)))
        }

        let archPath = CGMutablePath()
        archPath.addLines(between: pts)

        // 物理エッジ
        let archBody = SKPhysicsBody(edgeChainFrom: archPath)
        archBody.categoryBitMask  = Cat.wall
        archBody.collisionBitMask = Cat.ball
        archBody.restitution = Tuning.wallRestitution
        archBody.friction    = Tuning.wallFriction
        let archNode = SKNode()
        archNode.physicsBody = archBody
        addChild(archNode)

        // 描画
        let archShape = SKShapeNode()
        archShape.path        = archPath
        archShape.strokeColor = SKColor(red: 0.86, green: 0.86, blue: 1.0, alpha: 0.85)
        archShape.lineWidth   = 5
        addChild(archShape)
    }

    // MARK: - Slingshot Setup

    private func setupSlingshots() {
        // スリングショット本体（ボールに強い反発を与える斜め壁）
        // canvas: makeSeg(0.14, 0.22, 0.24, 0.14)
        //   a: sc(0.14, 0.22) = (54.6, 483.6) → SK (54.6, 216.4)
        //   b: sc(0.24, 0.14) = (93.6, 533.2) → SK (93.6, 166.8)
        let slingDefs: [(CGPoint, CGPoint)] = [
            (CGPoint(x: 54.6,  y: 216.4), CGPoint(x: 93.6,  y: 166.8)),  // 左
            (CGPoint(x: 335.4, y: 216.4), CGPoint(x: 296.4, y: 166.8)),  // 右
        ]
        for (a, b) in slingDefs {
            let node = SKNode()
            let body = SKPhysicsBody(edgeFrom: a, to: b)
            body.categoryBitMask    = Cat.sling
            body.collisionBitMask   = Cat.ball
            body.contactTestBitMask = Cat.ball
            body.restitution        = Tuning.slingRestitution
            body.friction           = 0
            node.physicsBody = body

            let shape = SKShapeNode()
            let path = CGMutablePath(); path.move(to: a); path.addLine(to: b)
            shape.path        = path
            shape.strokeColor = SKColor(red: 1.0, green: 0.43, blue: 0.0, alpha: 1.0)
            shape.lineWidth   = 7
            node.addChild(shape)
            addChild(node)
        }
    }

    // MARK: - Bumper Setup

    private func setupBumpers() {
        // バンパー配置 (SpriteKit 座標)
        // sc(0.50, 0.78) = (195, 620*0.22) = (195, 136.4) → SK (195, 563.6)
        // sc(0.28, 0.65) = (109.2, 620*0.35) = (109.2, 217) → SK (109.2, 483)
        // sc(0.72, 0.65) = (280.8, 217) → SK (280.8, 483)
        let bumperPos: [CGPoint] = [
            CGPoint(x: 195,   y: 563.6),
            CGPoint(x: 109.2, y: 483),
            CGPoint(x: 280.8, y: 483),
        ]
        for pos in bumperPos {
            // 外円（物理ボディ）
            let bumper = SKShapeNode(circleOfRadius: BUMP_R)
            bumper.position = pos
            bumper.fillColor   = SKColor(red: 0.047, green: 0.047, blue: 0.133, alpha: 1)
            bumper.strokeColor = SKColor(red: 0.7, green: 0.63, blue: 0.24, alpha: 0.8)
            bumper.lineWidth   = 2.5
            bumper.glowWidth   = 6

            let body = SKPhysicsBody(circleOfRadius: BUMP_R)
            body.isDynamic          = false
            body.categoryBitMask    = Cat.bumper
            body.collisionBitMask   = Cat.ball
            body.contactTestBitMask = Cat.ball
            body.restitution        = Tuning.bumperRestitution
            body.friction           = 0
            bumper.physicsBody = body

            // 内コア（装飾）
            let core = SKShapeNode(circleOfRadius: BUMP_R * 0.42)
            core.fillColor   = SKColor(red: 1.0, green: 0.84, blue: 0.0, alpha: 1)
            core.strokeColor = .clear
            core.glowWidth   = 5
            bumper.addChild(core)

            // 得点ラベル
            let label = SKLabelNode(text: "100")
            label.fontName = "Helvetica-Bold"
            label.fontSize = 9
            label.fontColor = SKColor(white: 0, alpha: 0.75)
            label.verticalAlignmentMode = .center
            bumper.addChild(label)

            addChild(bumper)
            bumperNodes.append(bumper)
        }
    }

    // MARK: - Target Setup

    private func setupTargets() {
        // ターゲット配置 (SpriteKit 座標)
        // sc(0.25, 0.47) = (97.5, 620*0.53) = (97.5, 328.6) → SK (97.5, 371.4)
        // sc(0.50, 0.47) = (195, 328.6) → SK (195, 371.4)
        // sc(0.75, 0.47) = (292.5, 328.6) → SK (292.5, 371.4)
        // sc(0.50, 0.57) = (195, 620*0.43) = (195, 266.6) → SK (195, 433.4)
        let targetPos: [CGPoint] = [
            CGPoint(x: 97.5,  y: 371.4),
            CGPoint(x: 195,   y: 371.4),
            CGPoint(x: 292.5, y: 371.4),
            CGPoint(x: 195,   y: 433.4),
        ]
        for (i, pos) in targetPos.enumerated() {
            let tPath = UIBezierPath(
                roundedRect: CGRect(x: -TW/2, y: -TH/2, width: TW, height: TH),
                cornerRadius: 4
            )
            let target = SKShapeNode(path: tPath.cgPath)
            target.position  = pos
            target.fillColor   = SKColor(red: 0.0, green: 0.27, blue: 0.8, alpha: 1)
            target.strokeColor = SKColor(red: 0.27, green: 0.67, blue: 1.0, alpha: 1)
            target.glowWidth   = 6

            let body = SKPhysicsBody(rectangleOf: CGSize(width: TW, height: TH))
            body.isDynamic          = false
            body.categoryBitMask    = Cat.target
            body.collisionBitMask   = Cat.ball
            body.contactTestBitMask = Cat.ball
            body.restitution        = Tuning.targetRestitution
            body.friction           = Tuning.targetFriction
            target.physicsBody = body

            let pts = targetPoints[i]
            let label = SKLabelNode(text: "\(pts)")
            label.fontName  = "Helvetica-Bold"
            label.fontSize  = 10
            label.fontColor = .white
            label.verticalAlignmentMode = .center
            target.addChild(label)

            addChild(target)
            targetNodes.append(target)
        }
    }

    // MARK: - Flipper Setup

    private func setupFlippers() {
        lFlipNode = makeFlipperNode(pivotX: LPX, dir: 1)
        rFlipNode = makeFlipperNode(pivotX: RPX, dir: -1)
        lFlipNode.zRotation = lRestAngle
        rFlipNode.zRotation = rRestAngle
        addChild(lFlipNode)
        addChild(rFlipNode)
    }

    /// フリッパーノードを生成する。
    /// dir=+1: 先端が右方向(左フリッパー) / dir=-1: 先端が左方向(右フリッパー)
    private func makeFlipperNode(pivotX: CGFloat, dir: CGFloat) -> SKNode {
        let node = SKNode()
        node.position = CGPoint(x: pivotX, y: FY)

        // 物理ボディ（isDynamic=false: 自らは動かないが衝突判定は持つ）
        let tipX = dir * FL
        let body = SKPhysicsBody(edgeFrom: .zero, to: CGPoint(x: tipX, y: 0))
        body.isDynamic          = false
        body.categoryBitMask    = Cat.flipper
        body.collisionBitMask   = Cat.ball
        body.contactTestBitMask = Cat.ball
        body.restitution        = Tuning.flipperRestitution
        body.friction           = Tuning.flipperFriction
        node.physicsBody = body

        // 描画（白い線 + シアングロー）
        let shape = SKShapeNode()
        let path = CGMutablePath()
        path.move(to: .zero)
        path.addLine(to: CGPoint(x: tipX, y: 0))
        shape.path        = path
        shape.strokeColor = .white
        shape.lineWidth   = FW
        shape.lineCap     = .round
        shape.glowWidth   = 8
        node.addChild(shape)

        // ピボットキャップ（円）
        let cap = SKShapeNode(circleOfRadius: 2.5)
        cap.fillColor   = .white
        cap.strokeColor = SKColor(white: 0.67, alpha: 1)
        cap.lineWidth   = 1.2
        node.addChild(cap)

        return node
    }

    // MARK: - HUD Setup

    private func setupHUD() {
        // ── スコアパネル（上部中央・目立つデザイン）──────────────
        // 半透明の背景パネル
        let scoreBg = SKShapeNode(rectOf: CGSize(width: 170, height: 58), cornerRadius: 14)
        scoreBg.position    = CGPoint(x: CW / 2, y: CH - 37)
        scoreBg.fillColor   = SKColor(red: 0.0, green: 0.0, blue: 0.0, alpha: 0.55)
        scoreBg.strokeColor = SKColor(white: 1.0, alpha: 0.10)
        scoreBg.lineWidth   = 1
        scoreBg.zPosition   = 5
        addChild(scoreBg)

        // "SCORE" サブタイトル
        let scoreTitleLabel = SKLabelNode(text: "SCORE")
        scoreTitleLabel.fontName                = "Helvetica-Bold"
        scoreTitleLabel.fontSize                = 10
        scoreTitleLabel.fontColor               = SKColor(white: 0.5, alpha: 1)
        scoreTitleLabel.position                = CGPoint(x: CW / 2, y: CH - 20)
        scoreTitleLabel.horizontalAlignmentMode = .center
        scoreTitleLabel.zPosition               = 6
        addChild(scoreTitleLabel)

        // スコア本体（大きく・中央揃え）
        scoreLabel = SKLabelNode(text: "0")
        scoreLabel.fontName                = "Helvetica-Bold"
        scoreLabel.fontSize                = 38
        scoreLabel.fontColor               = .white
        scoreLabel.position                = CGPoint(x: CW / 2, y: CH - 55)
        scoreLabel.horizontalAlignmentMode = .center
        scoreLabel.zPosition               = 6
        addChild(scoreLabel)

        // ── 残機（右下）──────────────────────────────────────────
        // "BALLS" ラベル
        let ballsTitleLabel = SKLabelNode(text: "BALLS")
        ballsTitleLabel.fontName                = "Helvetica-Bold"
        ballsTitleLabel.fontSize                = 10
        ballsTitleLabel.fontColor               = SKColor(white: 0.45, alpha: 1)
        ballsTitleLabel.position                = CGPoint(x: CW - 14, y: 86)
        ballsTitleLabel.horizontalAlignmentMode = .right
        addChild(ballsTitleLabel)

        // ●●● ドット（右下）
        ballsLabel = SKLabelNode(text: "●●●")
        ballsLabel.fontName                = "Helvetica"
        ballsLabel.fontSize                = 22
        ballsLabel.fontColor               = SKColor(red: 0.0, green: 0.9, blue: 1.0, alpha: 1)
        ballsLabel.position                = CGPoint(x: CW - 14, y: 60)
        ballsLabel.horizontalAlignmentMode = .right
        addChild(ballsLabel)

        // ── 2倍スコアタイマー（左下・非表示で待機）──────────────
        doubleScoreLabel = SKLabelNode(text: "")
        doubleScoreLabel.fontName                = "Helvetica-Bold"
        doubleScoreLabel.fontSize                = 14
        doubleScoreLabel.fontColor               = SKColor(red: 1.0, green: 0.84, blue: 0.0, alpha: 1)
        doubleScoreLabel.position                = CGPoint(x: 14, y: 80)
        doubleScoreLabel.horizontalAlignmentMode = .left
        doubleScoreLabel.isHidden                = true
        addChild(doubleScoreLabel)
    }

    private func refreshBallsHUD(ballsLeft: Int) {
        var s = ""
        for i in 0..<MAX_BALLS { s += i < ballsLeft ? "●" : "○" }
        ballsLabel.text = s
    }

    // MARK: - Ball Launch

    func launchBall() {
        ballNode?.removeFromParent()
        let ball = SKShapeNode(circleOfRadius: BR)

        // ── 発射位置 ──────────────────────────────────────────
        // FY = フリッパーピボットY。BR*2 上に配置してフリッパーと干渉しないようにする
        ball.position = CGPoint(x: LPX + 20, y: FY + BR * 4)  // ← 左フリッパー上(LPX+20)

        ball.fillColor   = .white
        ball.strokeColor = SKColor(red: 0.63, green: 0.63, blue: 0.86, alpha: 0.6)
        ball.lineWidth   = 1.2
        ball.glowWidth   = 10

        let body = SKPhysicsBody(circleOfRadius: BR)
        body.isDynamic      = true
        body.density        = 1.0

        // ── ボール物理パラメータ ──────────────────────────────
        body.restitution    = Tuning.ballRestitution
        body.friction       = Tuning.ballFriction
        body.linearDamping  = Tuning.ballDamping
        body.angularDamping = 0.1    // ← 回転減衰
        body.allowsRotation = false
        body.usesPreciseCollisionDetection = true
        body.categoryBitMask    = Cat.ball
        body.collisionBitMask   = Cat.wall | Cat.bumper | Cat.flipper | Cat.target | Cat.sling
        body.contactTestBitMask = Cat.bumper | Cat.target | Cat.sling | Cat.flipper
        ball.physicsBody = body
        addChild(ball)
        ballNode = ball
        ballDrainPending = false

        // ── 発射初速 ──────────────────────────────────────────
        // SpriteKit は Y 上向き正。dx で左右の振り分け、dy で上方向の打ち出し。
        // 重力が -300 px/s² なので、dy は最低 300 以上ないと即落下する。
        let vx: CGFloat = Bool.random() ? Tuning.launchVX : -Tuning.launchVX
        let vy: CGFloat = Tuning.launchVY
        body.velocity = CGVector(dx: vx, dy: vy)
    }

    // MARK: - Game Loop (update)

    override func update(_ currentTime: TimeInterval) {
        let dt: CGFloat = lastUpdateTime == 0 ? 0 : min(CGFloat(currentTime - lastUpdateTime), 1.0/30)
        lastUpdateTime = currentTime

        // フリッパー角度更新
        updateFlipperAngle(node: lFlipNode,
                           raised: lFlipRaised,
                           restAngle: lRestAngle, activeAngle: lActiveAngle,
                           isRaising: &isLFlipRaising, dt: dt)
        updateFlipperAngle(node: rFlipNode,
                           raised: rFlipRaised,
                           restAngle: rRestAngle, activeAngle: rActiveAngle,
                           isRaising: &isRFlipRaising, dt: dt)

        // ターゲット再点灯タイマー
        for i in 0..<targetStates.count {
            if !targetStates[i].active {
                targetStates[i].restore -= Double(dt)
                if targetStates[i].restore <= 0 {
                    activateTarget(at: i)
                }
            }
        }

        // バンパー発光タイマー
        for i in 0..<bumperFlash.count {
            if bumperFlash[i] > 0 {
                bumperFlash[i] -= Double(dt)
                updateBumperAppearance(at: i)
            }
        }

        // ⚠️ 追加: 2倍スコアタイマー
                if doubleScoreTimer > 0 {
                    doubleScoreTimer -= Double(dt)
                    if doubleScoreTimer <= 0 {
                        doubleScoreTimer = 0
                        doubleScoreLabel.isHidden = true
                    } else {
                        doubleScoreLabel.text = "×2  \(Int(ceil(doubleScoreTimer)))s"
                    }
                }
        // スコアポップアップ更新（上に浮かびながらフェードアウト）
        for i in (0..<popups.count).reversed() {
            popups[i].node.position.y += popups[i].vy * dt  // popups[i].vy ← 上昇速度 (px/s)
            popups[i].alpha -= 2.2 * dt  // ← フェードアウト速度 (大きいほど早く消える)
            popups[i].node.alpha = max(0, popups[i].alpha)
            if popups[i].alpha <= 0 {
                popups[i].node.removeFromParent()
                popups.remove(at: i)
            }
        }

        // ドレイン判定（ボールが画面下に消えたとき）
        if let ball = ballNode, ball.position.y < -BR * 4, !ballDrainPending {
            ballDrainPending = true
            ball.physicsBody?.isDynamic = false
            ball.removeFromParent()
            ballNode = nil
            onBallDrained?()
        }
    }

    // MARK: - Flipper Angle Update

    /// フリッパーを目標角度に向けて滑らかに回転させる
    private func updateFlipperAngle(
        node: SKNode, raised: Bool,
        restAngle: CGFloat, activeAngle: CGFloat,
        isRaising: inout Bool, dt: CGFloat
    ) {
        let target = raised ? activeAngle : restAngle
        let diff   = target - node.zRotation
        guard abs(diff) > 0.001 else {
            isRaising = false
            return
        }
        let speed = diff * (activeAngle - restAngle) > 0 ? raiseSpeed : lowerSpeed
        let step  = (diff < 0 ? -1 : 1) * min(abs(diff), speed * dt)
        node.zRotation += step
        // raising フラグ: 上げ方向に動いている最中（スラップブースト判定に使う）
        isRaising = raised && abs(node.zRotation - activeAngle) > 0.05
    }

    // MARK: - Contact Detection

    func didBegin(_ contact: SKPhysicsContact) {
        let bodyA = contact.bodyA, bodyB = contact.bodyB

        // ボール vs 相手 を特定する
        guard let ballBody = (bodyA.categoryBitMask == Cat.ball ? bodyA :
                              bodyB.categoryBitMask == Cat.ball ? bodyB : nil)
        else { return }
        let other = (ballBody === bodyA) ? bodyB : bodyA

        switch other.categoryBitMask {

        case Cat.bumper:
            handleBumperHit(ballBody: ballBody, bumperNode: other.node)

        case Cat.sling:
            handleSlingHit(ballBody: ballBody, contact: contact)

        case Cat.target:
            handleTargetHit(ballBody: ballBody, targetNode: other.node)

        case Cat.flipper:
            handleFlipperHit(ballBody: ballBody, flipperNode: other.node)

        default: break
        }
    }

    private func handleBumperHit(ballBody: SKPhysicsBody, bumperNode: SKNode?) {
        guard let bNode = bumperNode as? SKShapeNode,
              let bIdx  = bumperNodes.firstIndex(of: bNode) else { return }

        // バンパーからボールを弾き飛ばす（最低速度を保証）
        if let ballNode = ballNode {
            let dx = ballNode.position.x - bNode.position.x
            let dy = ballNode.position.y - bNode.position.y
            let len = sqrt(dx*dx + dy*dy)
            guard len > 0 else { return }
            let nx = dx/len, ny = dy/len
            let minSpeed: CGFloat = Tuning.bumperMinSpeed
            let spd = sqrt(pow(ballBody.velocity.dx, 2) + pow(ballBody.velocity.dy, 2))
            let ns  = max(spd, minSpeed)
            ballBody.velocity = CGVector(dx: nx * ns, dy: ny * ns)
        }

        // 発光タイマーセット
        bumperFlash[bIdx] = Tuning.bumperFlashDur
        updateBumperAppearance(at: bIdx)

        // スコア
        addScore(100, at: bNode.position)
    }

    private func handleSlingHit(ballBody: SKPhysicsBody, contact: SKPhysicsContact) {
        // スリングは restitution=1.1 で自動反射 + 法線方向に追加インパルス
        let norm = contact.contactNormal
        ballBody.velocity = CGVector(
            dx: ballBody.velocity.dx + norm.dx * Tuning.slingImpulse,
            dy: ballBody.velocity.dy + norm.dy * Tuning.slingImpulse
        )
        clampBallSpeed(ballBody: ballBody)
        addScore(500, at: contact.contactPoint)
    }

    private func handleTargetHit(ballBody: SKPhysicsBody, targetNode: SKNode?) {
        guard let tNode = targetNode as? SKShapeNode,
              let tIdx  = targetNodes.firstIndex(of: tNode),
              targetStates[tIdx].active
        else { return }

        deactivateTarget(at: tIdx)

        // 10000pt ターゲット → 追加ボール（マルチボール）は省略（残機管理が複雑になるため）代替として10000ptターゲット(index 3)ヒット → 2倍スコアタイム発動
        if targetPoints[tIdx] == 10000 {
                    doubleScoreTimer = Tuning.doubleScoreDuration
                    doubleScoreLabel.text   = "×2  \(Int(Tuning.doubleScoreDuration))s"
                    doubleScoreLabel.isHidden = false
                }
        addScore(targetPoints[tIdx], at: tNode.position)
    }

    private func handleFlipperHit(ballBody: SKPhysicsBody, flipperNode: SKNode?) {
        guard let fNode = flipperNode else { return }
        // スラップブースト: フリッパーが上昇中にヒットした場合のみ追加加速
        let isLeft = fNode === lFlipNode
        if (isLeft && isLFlipRaising) || (!isLeft && isRFlipRaising) {
            let dir: CGFloat = isLeft ? 1 : -1
            ballBody.velocity = CGVector(
                dx: ballBody.velocity.dx + dir * Tuning.slapBoostDX,
                dy: ballBody.velocity.dy + Tuning.slapBoostDY
            )
            clampBallSpeed(ballBody: ballBody)
        }
    }

    // MARK: - Target State

    private func deactivateTarget(at index: Int) {
        targetStates[index].active  = false
        targetStates[index].restore = Tuning.targetRestoreSec
        let node = targetNodes[index]
        node.physicsBody = nil
        node.fillColor   = SKColor(red: 0.067, green: 0.067, blue: 0.157, alpha: 1)
        node.strokeColor = SKColor(red: 0.165, green: 0.165, blue: 0.314, alpha: 1)
        node.glowWidth   = 0
        if let label = node.children.first as? SKLabelNode {
            label.fontColor = SKColor(red: 0.2, green: 0.2, blue: 0.33, alpha: 1)
        }
    }

    private func activateTarget(at index: Int) {
        targetStates[index].active  = true
        targetStates[index].restore = Tuning.targetRestoreSec
        let node = targetNodes[index]
        let body = SKPhysicsBody(rectangleOf: CGSize(width: TW, height: TH))
            body.isDynamic          = false
            body.categoryBitMask    = Cat.target
            body.collisionBitMask   = Cat.ball
            body.contactTestBitMask = Cat.ball
            body.restitution        = Tuning.targetRestitution
            body.friction           = Tuning.targetFriction
            node.physicsBody = body
        node.fillColor   = SKColor(red: 0.0, green: 0.27, blue: 0.8, alpha: 1)
        node.strokeColor = SKColor(red: 0.27, green: 0.67, blue: 1.0, alpha: 1)
        node.glowWidth   = 6
        if let label = node.children.first as? SKLabelNode {
            label.fontColor = .white
        }
    }

    // MARK: - Bumper Appearance

    private func updateBumperAppearance(at index: Int) {
        let node = bumperNodes[index]
        let fl   = bumperFlash[index] > 0
        node.strokeColor = fl ? .white : SKColor(red: 0.7, green: 0.63, blue: 0.24, alpha: 0.8)
        node.glowWidth   = fl ? 20 : 6
        if let core = node.children.first as? SKShapeNode {
            core.fillColor = fl ? .white : SKColor(red: 1.0, green: 0.84, blue: 0.0, alpha: 1)
            core.glowWidth = fl ? 12 : 5
        }
    }

    // MARK: - Score

    private func addScore(_ pts: Int, at pos: CGPoint) {
        let actual = doubleScoreTimer > 0 ? pts * 2 : pts
        internalScore += actual
        onScoreChanged?(internalScore)
        scoreLabel.text = "\(internalScore)"

        // ポップアップ
        let col = pts >= 10000 ? SKColor(red: 1.0, green: 0.84, blue: 0.0, alpha: 1) :
                  pts >= 1000  ? SKColor(red: 1.0, green: 0.43, blue: 0.0, alpha: 1) : .white
        let popup = SKLabelNode(text: "+\(actual)")
        popup.fontName  = "Helvetica-Bold"
        popup.fontSize  = 17
        popup.fontColor = col
        popup.position  = pos
        addChild(popup)
        popups.append(Popup(node: popup))
    }

    // MARK: - Speed Clamp

    private func clampBallSpeed(ballBody: SKPhysicsBody) {
        // ボール最高速度の上限クランプ（バンパー連打による無限加速防止）
        let maxSpeed: CGFloat = Tuning.maxSpeed
        let spd = sqrt(pow(ballBody.velocity.dx, 2) + pow(ballBody.velocity.dy, 2))
        if spd > maxSpeed {
            let s = maxSpeed / spd
            ballBody.velocity = CGVector(dx: ballBody.velocity.dx * s, dy: ballBody.velocity.dy * s)
        }
    }

    // MARK: - Touch Input

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches {
            let x = touch.location(in: self).x
            if x < CW / 2 { lFlipRaised = true } else { rFlipRaised = true }
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        syncFlipperState(touches: event?.allTouches)
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        lFlipRaised = false; rFlipRaised = false
    }

    private func syncFlipperState(touches: Set<UITouch>?) {
        var hasLeft = false, hasRight = false
        for t in touches ?? [] {
            guard t.phase != .ended && t.phase != .cancelled else { continue }
            let x = t.location(in: self).x
            if x < CW / 2 { hasLeft = true } else { hasRight = true }
        }
        lFlipRaised = hasLeft
        rFlipRaised = hasRight
    }

    // MARK: - Reset

    /// 外部から呼ばれるゲームリセット（再スタート時）
    func resetGame(ballsLeft: Int) {
        internalScore = 0
        scoreLabel.text = "0"
        ballDrainPending = false
        lFlipRaised = false; rFlipRaised = false

        // 2倍タイムをリセット
                doubleScoreTimer = 0
                doubleScoreLabel.isHidden = true
        // ターゲット・バンパーを初期状態に
        for i in 0..<targetStates.count { activateTarget(at: i) }
        for i in 0..<bumperFlash.count  { bumperFlash[i] = 0; updateBumperAppearance(at: i) }
        popups.forEach { $0.node.removeFromParent() }
        popups.removeAll()

        refreshBallsHUD(ballsLeft: ballsLeft)
        ballNode?.removeFromParent()
        launchBall()
    }

    /// 残機HUDを更新する（PinballView から呼ばれる）
    func updateBallsHUD(ballsLeft: Int) {
        refreshBallsHUD(ballsLeft: ballsLeft)
    }
}
