//
//  CoinDropScene.swift
//  FDL-TenBlitz
//
//  Created by 空飛ぶ研究室(FlyingDevLab) on 2026/05/30.
//
//  コインを落とし、掴んで動かし、同種コインを集めて合体させ、
//  最終的に 50¢×2 → $1 を作るスイカ系の物理パズルシーン。
//
//  役割分担:
//    - Scene  : 物理シミュレーション・出現・ドラッグ・合体・溢れ判定
//    - VM      : スコア／残り秒数／次コイン／画面遷移（CoinDropViewModel）
//  PinballScene と同じく、状態は VM へコールバックで通知する。
//
//  座標系: SpriteKit（Y 上向き / 原点左下）。フィールドは固定サイズで
//          scaleMode=.aspectFit によりデバイスへフィットさせる。

import SpriteKit
import UIKit

// MARK: - ⚙️ 調整パラメータ（ここだけ触ればOK）
//
// ┌─────────────────────────────────────────────────────────────┐
// │  CoinDrop の数値定数を一箇所に集約。挙動を変えたいときは     │
// │  ここだけ編集する。（コインの半径・色は CoinType 側）        │
// └─────────────────────────────────────────────────────────────┘

enum CoinDropTuning {

    // ── 物理ワールド ──────────────────────────────────────────
    /// 重力 (マイナス=下向き)。大きいほど速く落ちる
    static let gravity:        CGFloat = -9.0
    /// コイン反発係数 (0=弾まない / 1=完全弾性)。低めにして積みやすく
    static let restitution:    CGFloat = 0.18
    /// コイン摩擦 (大きいほど滑りにくく安定して積める)
    static let friction:       CGFloat = 0.6
    /// 空気抵抗 (大きいほどふわっと落ちる)
    static let linearDamping:  CGFloat = 0.4
    /// 回転減衰
    static let angularDamping: CGFloat = 0.6

    // ── ゲーム進行 ────────────────────────────────────────────
    /// 制限時間 (秒)
    static let gameDuration:   TimeInterval = 60
    /// コイン出現間隔 (秒)
    static let spawnInterval:  TimeInterval = 1.0
    /// 出現位置の左右ブレ（フィールド幅に対する割合 ±）
    static let spawnSpread:    CGFloat = 0.20

    // ── 合体判定 ──────────────────────────────────────────────
    /// 「接触している」とみなす中心間距離の余裕 (pt)。
    /// 半径×2 + この値 以内なら同グループ扱い
    static let mergeTolerance: CGFloat = 6

    // ── 溢れ判定 ──────────────────────────────────────────────
    /// 出現直後の猶予 (秒)。落下中のコインで誤判定しないため
    static let overflowGrace:     TimeInterval = 1.2
    /// 「静止した」とみなす速度しきい値 (pt/s)
    static let overflowRestSpeed: CGFloat = 45

    // ── レイアウト ────────────────────────────────────────────
    /// 左右壁とコインの最小すき間
    static let wallInset:      CGFloat = 4
    /// 天井からドロップ位置までの距離 (pt)
    static let spawnTopOffset: CGFloat = 46
    /// 天井から危険ライン（溢れ判定ライン）までの距離 (pt)
    static let overflowOffset: CGFloat = 84
}

// MARK: - Physics Categories

private struct Cat {
    static let coin:  UInt32 = 1 << 0
    static let wall:  UInt32 = 1 << 1
    static let floor: UInt32 = 1 << 2
}

// MARK: - CoinNode
// SKShapeNode を継承し、コイン種別と生成時刻を保持する。
// （userData ではなく型付きプロパティで持つことで取り回しを明確にする）

final class CoinNode: SKShapeNode {
    var coinType: CoinType = .penny
    var bornAt:   TimeInterval = 0
}

// MARK: - CoinDropScene

final class CoinDropScene: SKScene, SKPhysicsContactDelegate {

    // ── フィールド寸法（didMove で size から確定）──────────────
    private var W: CGFloat = 390
    private var H: CGFloat = 820
    private var spawnY:    CGFloat = 0   // ドロップ位置 Y
    private var overflowY: CGFloat = 0   // 危険ライン Y

    // ── 出現順（1¢→5¢→10¢→25¢→50¢→ループ）──────────────
    private let sequence: [CoinType] = [.penny, .nickel, .dime, .quarter, .halfDollar]
    private var spawnIndex = 0
    private var spawnAccumulator: TimeInterval = 0

    // ── 状態 ──────────────────────────────────────────────────
    private var coins: [CoinNode] = []
    private var draggedNode: CoinNode?
    private var score = 0
    private var timeRemaining: TimeInterval = CoinDropTuning.gameDuration
    private var lastReportedSecond = Int(CoinDropTuning.gameDuration)
    private var lastUpdateTime: TimeInterval = 0
    private var lastLandSound:  TimeInterval = 0
    private var zCounter: Int = 10
    private var isRunning = false   // 進行中フラグ（ゲームオーバー後は false）

    // ── セットアップ済みフラグ（didMove 二重呼び出し対策）──────
    // SKView に同一シーンが再提示されると didMove が再度呼ばれ、
    // 壁ノードが重複追加されるのを防ぐ（Pinball と同じ保護）。
    private var isSetupDone = false

    // ── Callbacks（VM へ通知）─────────────────────────────────
    var onScoreChanged:   ((Int) -> Void)?
    var onSecondsChanged: ((Int) -> Void)?
    var onNextCoinChanged: ((CoinType) -> Void)?
    var onGameOver:       ((CoinDropGameOverReason) -> Void)?

    // MARK: - Setup

    override func didMove(to view: SKView) {
        guard !isSetupDone else { return }
        isSetupDone = true

        W = size.width
        H = size.height
        spawnY    = H - CoinDropTuning.spawnTopOffset
        overflowY = H - CoinDropTuning.overflowOffset

        backgroundColor = .clear   // SpriteView は allowsTransparency。アプリの背景(DS.bg)を透過

        physicsWorld.gravity = CGVector(dx: 0, dy: CoinDropTuning.gravity)
        physicsWorld.contactDelegate = self

        setupBounds()
        drawDangerLine()
    }

    /// 左右の壁・床を構築する
    private func setupBounds() {
        // 床
        let floor = SKNode()
        let fBody = SKPhysicsBody(edgeFrom: CGPoint(x: 0, y: 0), to: CGPoint(x: W, y: 0))
        fBody.categoryBitMask = Cat.floor
        fBody.friction = CoinDropTuning.friction
        floor.physicsBody = fBody
        addChild(floor)

        // 左右の壁（上方向へ延長してドラッグ中のコインがはみ出さないように）
        for x in [CGFloat(0), W] {
            let wall = SKNode()
            let wBody = SKPhysicsBody(edgeFrom: CGPoint(x: x, y: -40), to: CGPoint(x: x, y: H + 200))
            wBody.categoryBitMask = Cat.wall
            wBody.friction = CoinDropTuning.friction
            wall.physicsBody = wBody
            addChild(wall)
        }

        // 床ライン描画（薄いグレー）
        let floorShape = SKShapeNode()
        let fp = CGMutablePath()
        fp.move(to: CGPoint(x: 0, y: 1)); fp.addLine(to: CGPoint(x: W, y: 1))
        floorShape.path        = fp
        floorShape.strokeColor = SKColor(white: 0.0, alpha: 0.10)
        floorShape.lineWidth   = 2
        floorShape.zPosition   = 1
        addChild(floorShape)
    }

    /// 危険ライン（溢れ判定ライン）を破線で描画する
    private func drawDangerLine() {
        let dashed = SKShapeNode()
        let p = CGMutablePath()
        p.move(to: CGPoint(x: 8, y: overflowY)); p.addLine(to: CGPoint(x: W - 8, y: overflowY))
        let pattern: [CGFloat] = [10, 8]
        dashed.path        = p.copy(dashingWithPhase: 0, lengths: pattern)
        dashed.strokeColor = SKColor(red: 0.85, green: 0.35, blue: 0.30, alpha: 0.45)
        dashed.lineWidth   = 2
        dashed.zPosition   = 1
        addChild(dashed)
    }

    // MARK: - Game Loop

    override func update(_ currentTime: TimeInterval) {
        let dt: TimeInterval = lastUpdateTime == 0 ? 0 : min(currentTime - lastUpdateTime, 1.0 / 30.0)
        lastUpdateTime = currentTime
        guard isRunning else { return }

        // ── 残り時間 ─────────────────────────────────────────
        timeRemaining -= dt
        let secs = max(0, Int(ceil(timeRemaining)))
        if secs != lastReportedSecond {
            lastReportedSecond = secs
            onSecondsChanged?(secs)
        }
        if timeRemaining <= 0 {
            endGame(reason: .timeUp)
            return
        }

        // ── コイン出現 ───────────────────────────────────────
        spawnAccumulator += dt
        if spawnAccumulator >= CoinDropTuning.spawnInterval {
            spawnAccumulator -= CoinDropTuning.spawnInterval
            spawnNextCoin()
        }

        // ── 合体（1フレーム1合体。連鎖は次フレームへ持ち越す）──
        scanAndMergeOnce()

        // ── 溢れ判定 ─────────────────────────────────────────
        checkOverflow(currentTime: currentTime)
    }

    // MARK: - Spawn

    private func spawnNextCoin() {
        let type = sequence[spawnIndex % sequence.count]
        spawnIndex += 1
        spawnCoin(type: type)
        // 次に落ちるコインをプレビューへ通知
        onNextCoinChanged?(sequence[spawnIndex % sequence.count])
    }

    private func spawnCoin(type: CoinType) {
        let r = type.radius
        let minX = r + CoinDropTuning.wallInset
        let maxX = W - r - CoinDropTuning.wallInset
        let half = W * CoinDropTuning.spawnSpread
        let x = max(minX, min(maxX, W / 2 + CGFloat.random(in: -half...half)))

        let coin = makeCoin(type: type, at: CGPoint(x: x, y: spawnY))
        addChild(coin)
        coins.append(coin)
    }

    private func makeCoin(type: CoinType, at pos: CGPoint) -> CoinNode {
        let r = type.radius
        let coin = CoinNode()
        coin.coinType = type
        coin.bornAt   = lastUpdateTime
        coin.path     = UIBezierPath(ovalIn: CGRect(x: -r, y: -r, width: r * 2, height: r * 2)).cgPath
        coin.fillColor   = type.uiColor
        coin.strokeColor = UIColor(white: 0, alpha: 0.18)   // 縁取り（暗め）
        coin.lineWidth   = 2
        coin.position    = pos
        coin.zPosition   = nextZ()

        // 光沢ハイライト（左上）
        let hl = SKShapeNode(circleOfRadius: r * 0.5)
        hl.fillColor   = UIColor(white: 1, alpha: 0.22)
        hl.strokeColor = .clear
        hl.position    = CGPoint(x: -r * 0.25, y: r * 0.3)
        coin.addChild(hl)

        // ラベル（"1¢" など）。glowWidth は使わない
        let label = SKLabelNode(text: type.label)
        label.fontName  = "Helvetica-Bold"
        label.fontSize  = max(11, r * 0.6)
        label.fontColor = type.labelUIColor
        label.verticalAlignmentMode   = .center
        label.horizontalAlignmentMode = .center
        coin.addChild(label)

        // 物理ボディ
        let body = SKPhysicsBody(circleOfRadius: r)
        body.categoryBitMask    = Cat.coin
        body.collisionBitMask   = Cat.coin | Cat.wall | Cat.floor
        body.contactTestBitMask = Cat.coin | Cat.wall | Cat.floor
        body.restitution    = CoinDropTuning.restitution
        body.friction       = CoinDropTuning.friction
        body.linearDamping  = CoinDropTuning.linearDamping
        body.angularDamping = CoinDropTuning.angularDamping
        body.allowsRotation = false   // ラベルを正立させたままにする
        coin.physicsBody = body

        return coin
    }

    private func nextZ() -> CGFloat {
        zCounter += 1
        return CGFloat(zCounter)
    }

    // MARK: - Drag

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard isRunning, let touch = touches.first else { return }
        let p = touch.location(in: self)
        guard let coin = topCoin(at: p) else { return }
        draggedNode = coin
        coin.physicsBody?.isDynamic = false   // 重力を切って「持ち上げ」
        coin.physicsBody?.velocity  = .zero
        coin.zPosition = nextZ()              // 最前面へ
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first, let coin = draggedNode else { return }
        let p = touch.location(in: self)
        coin.position = clampedDragPosition(p, radius: coin.coinType.radius)
        coin.physicsBody?.velocity = .zero
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        releaseDrag()
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        releaseDrag()
    }

    /// 離したコインを自然落下に戻す
    private func releaseDrag() {
        guard let coin = draggedNode else { return }
        coin.physicsBody?.isDynamic = true
        coin.physicsBody?.velocity  = .zero
        coin.bornAt = lastUpdateTime   // 置いた瞬間から猶予を再付与（溢れ誤判定を防ぐ）
        draggedNode = nil
    }

    /// タッチ位置にある一番手前のコインを返す
    private func topCoin(at p: CGPoint) -> CoinNode? {
        var best: CoinNode?
        var bestZ: CGFloat = -1
        for c in coins {
            let d = hypot(c.position.x - p.x, c.position.y - p.y)
            if d <= c.coinType.radius + 6, c.zPosition >= bestZ {
                bestZ = c.zPosition
                best  = c
            }
        }
        return best
    }

    /// ドラッグ位置を壁・天井内にクランプする
    private func clampedDragPosition(_ p: CGPoint, radius r: CGFloat) -> CGPoint {
        let minX = r + CoinDropTuning.wallInset
        let maxX = W - r - CoinDropTuning.wallInset
        let minY = r + 2
        let maxY = H - r
        return CGPoint(x: min(max(p.x, minX), maxX),
                       y: min(max(p.y, minY), maxY))
    }

    // MARK: - Merge

    /// 全種について合体可能なグループを探し、見つかれば1件だけ合体する。
    /// 連鎖は次フレームの物理＋再スキャンで自然に処理される。
    private func scanAndMergeOnce() {
        for type in CoinType.allCases {
            let same = coins.filter { $0.coinType == type }
            guard same.count >= type.mergeCount else { continue }
            if let group = firstMergeableGroup(same, type: type) {
                performMerge(group: group, type: type)
                return
            }
        }
    }

    /// 同種コインを近接で連結成分に分け、枚数条件を満たす最初のグループを返す
    private func firstMergeableGroup(_ list: [CoinNode], type: CoinType) -> [CoinNode]? {
        let thresh = type.radius * 2 + CoinDropTuning.mergeTolerance
        var visited = Set<ObjectIdentifier>()

        for seed in list {
            let sid = ObjectIdentifier(seed)
            if visited.contains(sid) { continue }

            var stack: [CoinNode] = [seed]
            visited.insert(sid)
            var comp: [CoinNode] = []

            while let n = stack.popLast() {
                comp.append(n)
                for m in list {
                    let mid = ObjectIdentifier(m)
                    if visited.contains(mid) { continue }
                    let d = hypot(n.position.x - m.position.x, n.position.y - m.position.y)
                    if d <= thresh {
                        visited.insert(mid)
                        stack.append(m)
                    }
                }
            }
            if comp.count >= type.mergeCount { return comp }
        }
        return nil
    }

    /// グループ内から最も密集した必要枚数を合体させる
    private func performMerge(group: [CoinNode], type: CoinType) {
        let needed = type.mergeCount

        // グループ重心に近い順に並べ、必要枚数だけ採用（自然な合体位置に）
        let gcx = group.map { $0.position.x }.reduce(0, +) / CGFloat(group.count)
        let gcy = group.map { $0.position.y }.reduce(0, +) / CGFloat(group.count)
        let members = Array(group.sorted {
            hypot($0.position.x - gcx, $0.position.y - gcy) <
            hypot($1.position.x - gcx, $1.position.y - gcy)
        }.prefix(needed))

        let cx = members.map { $0.position.x }.reduce(0, +) / CGFloat(needed)
        let cy = members.map { $0.position.y }.reduce(0, +) / CGFloat(needed)
        let center = CGPoint(x: cx, y: cy)

        // ドラッグ中コインが消える場合はドラッグ解除
        let ids = Set(members.map { ObjectIdentifier($0) })
        if let dn = draggedNode, ids.contains(ObjectIdentifier(dn)) {
            draggedNode = nil
        }

        // 削除
        members.forEach { $0.removeFromParent() }
        coins.removeAll { ids.contains(ObjectIdentifier($0)) }

        if let into = type.mergesInto {
            // 次のコインを重心に生成
            let coin = makeCoin(type: into, at: center)
            coin.physicsBody?.velocity = .zero
            addChild(coin)
            coins.append(coin)
            SoundManager.shared.playCoinMerge()
            spawnMergeFlash(at: center, color: into.uiColor)
        } else {
            // 50¢×2 → $1 完成
            score += 1
            onScoreChanged?(score)
            SoundManager.shared.playDollarMade()
            SoundManager.shared.vibrate()
            spawnDollarPop(at: center)
        }
    }

    // MARK: - Overflow

    private func checkOverflow(currentTime: TimeInterval) {
        for c in coins {
            if c === draggedNode { continue }
            if currentTime - c.bornAt < CoinDropTuning.overflowGrace { continue }
            guard let b = c.physicsBody else { continue }
            let speed = hypot(b.velocity.dx, b.velocity.dy)
            if c.position.y > overflowY && speed < CoinDropTuning.overflowRestSpeed {
                endGame(reason: .overflow)
                return
            }
        }
    }

    // MARK: - Effects

    private func spawnMergeFlash(at pos: CGPoint, color: UIColor) {
        let ring = SKShapeNode(circleOfRadius: 8)
        ring.position    = pos
        ring.strokeColor = color
        ring.fillColor   = .clear
        ring.lineWidth   = 3
        ring.zPosition   = 998
        addChild(ring)
        ring.run(.sequence([
            .group([.scale(to: 4.0, duration: 0.3), .fadeOut(withDuration: 0.3)]),
            .removeFromParent()
        ]))
    }

    private func spawnDollarPop(at pos: CGPoint) {
        let label = SKLabelNode(text: "$1!")
        label.fontName  = "Helvetica-Bold"
        label.fontSize  = 30
        label.fontColor = SKColor(red: 0.95, green: 0.75, blue: 0.15, alpha: 1)
        label.position  = pos
        label.zPosition = 999
        addChild(label)
        label.run(.sequence([
            .group([
                .moveBy(x: 0, y: 80, duration: 0.7),
                .fadeOut(withDuration: 0.7),
                .scale(to: 1.5, duration: 0.7)
            ]),
            .removeFromParent()
        ]))
    }

    // MARK: - Contact (sound only)

    func didBegin(_ contact: SKPhysicsContact) {
        // 合体は距離ベースで毎フレーム判定するため、接触は着地音にのみ使う
        let now = lastUpdateTime
        if now - lastLandSound > 0.10 {
            lastLandSound = now
            SoundManager.shared.playCoinLand()
        }
    }

    private func endGame(reason: CoinDropGameOverReason) {
        guard isRunning else { return }
        isRunning = false
        SoundManager.shared.playGameOver()
        onGameOver?(reason)
    }

    // MARK: - Reset（開始・再スタート時に View から呼ぶ）

    func resetGame() {
        coins.forEach { $0.removeFromParent() }
        coins.removeAll()
        draggedNode = nil

        score             = 0
        spawnIndex        = 0
        spawnAccumulator  = CoinDropTuning.spawnInterval   // 開始直後に1枚目を落とす
        timeRemaining     = CoinDropTuning.gameDuration
        lastReportedSecond = Int(CoinDropTuning.gameDuration)
        lastLandSound     = 0
        zCounter          = 10
        isRunning         = true

        onScoreChanged?(0)
        onSecondsChanged?(Int(CoinDropTuning.gameDuration))
        onNextCoinChanged?(sequence[0])
    }
}
