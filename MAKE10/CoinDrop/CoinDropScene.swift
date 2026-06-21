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
//
//  ★ SpriteKit を初めて読む人へ ★
//    SpriteKit はゲーム用のフレームワークで、画面に表示される
//    キャラクターや背景を「ノード（Node）」という部品で管理します。
//    ノードをシーン（SKScene）に追加すると画面に表示され、
//    物理エンジン（SKPhysicsBody）を付けると重力や衝突が自動で計算されます。

import SpriteKit
import UIKit

// MARK: - ⚙️ 調整パラメータ（ここだけ触ればOK）
//
// ┌─────────────────────────────────────────────────────────────┐
// │  CoinDrop の数値定数を一箇所に集約。挙動を変えたいときは     │
// │  ここだけ編集する。（コインの半径・色は CoinType 側）        │
// └─────────────────────────────────────────────────────────────┘
//
// ★ enum を定数置き場として使う理由 ★
//   Swift では case のない enum はインスタンス化できないため、
//   定数をまとめるだけの「名前空間」として便利に使えます。
//   struct でも同じことはできますが、誤って new してしまう心配がなくなります。

enum CoinDropTuning {

    // ── 物理ワールド ──────────────────────────────────────────
    /// 重力 (マイナス=下向き)。大きいほど速く落ちる
    /// 現実の重力は約 -9.8 m/s² ですが、ゲームなので見栄えに合わせて調整しています
    static let gravity:        CGFloat = -9.0

    /// コイン反発係数 (0=弾まない / 1=完全弾性)。低めにして積みやすく
    /// 0.18 ≒ ほとんど弾まない。スタック系パズルはゆっくり落ちる方が遊びやすい
    static let restitution:    CGFloat = 0.18

    /// コイン摩擦 (大きいほど滑りにくく安定して積める)
    /// 壁や床・他のコインとの接触時に働く「ざらつき感」のパラメータ
    static let friction:       CGFloat = 0.6

    /// 空気抵抗 (大きいほどふわっと落ちる)
    /// linearDamping は「移動速度を毎フレーム少しずつ減衰させる」係数です
    static let linearDamping:  CGFloat = 0.4

    /// 回転減衰
    /// コインが回転したときに、時間とともに回転が止まる速さを表します
    static let angularDamping: CGFloat = 0.6

    // ── ゲーム進行 ────────────────────────────────────────────
    /// 制限時間 (秒)
    static let gameDuration:   TimeInterval = 60

    /// コイン出現間隔 (秒)
    /// この秒数ごとに自動で新しいコインが落ちてきます
    static let spawnInterval:  TimeInterval = 1.0

    /// 出現位置の左右ブレ（フィールド幅に対する割合 ±）
    /// 0.20 = 画面幅の ±20% の範囲でランダムに出現する。0 にすると常に中央から落ちる
    static let spawnSpread:    CGFloat = 0.20

    // ── 合体判定 ──────────────────────────────────────────────
    /// 「接触している」とみなす中心間距離の余裕 (pt)。
    /// 半径×2 + この値 以内なら同グループ扱い
    /// 物理エンジンの微妙なすき間を吸収するためのゆとり値です
    static let mergeTolerance: CGFloat = 6

    // ── 溢れ判定 ──────────────────────────────────────────────
    /// 出現直後の猶予 (秒)。落下中のコインで誤判定しないため
    /// コインは出現直後に危険ラインより上にいるので、落ち着くまで無視します
    static let overflowGrace:     TimeInterval = 1.2

    /// 「静止した」とみなす速度しきい値 (pt/s)
    /// この値より遅いコインを「動きが止まった＝積み上がった」と判断します
    static let overflowRestSpeed: CGFloat = 45

    // ── レイアウト ────────────────────────────────────────────
    /// 左右壁とコインの最小すき間
    /// コインが壁にめり込まないようにする余白（ポイント単位）
    static let wallInset:      CGFloat = 4

    /// 天井からドロップ位置までの距離 (pt)
    /// コインが画面上部から少し下がった位置に出現するための余白
    static let spawnTopOffset: CGFloat = 46

    /// 天井から危険ライン（溢れ判定ライン）までの距離 (pt)
    /// この赤破線を超えてコインが静止するとゲームオーバー
    static let overflowOffset: CGFloat = 84
}

// MARK: - Physics Categories
//
// ★ ビットマスクとは？ ★
//   物理エンジンは「どのオブジェクト同士が衝突するか」をビット演算で管理します。
//   1 << 0 = 0b001（コイン）
//   1 << 1 = 0b010（壁）
//   1 << 2 = 0b100（床）
//   AND 演算で共通ビットがあれば「関係あり」と判定されます。
//   こうすることで大量のオブジェクトの衝突判定を高速に処理できます。
//   （同じ説明を PinballScene.swift にも書いてしまっています。重複ごめんなさい🙇）

private struct Cat {
    /// コイン同士の衝突カテゴリ
    static let coin:  UInt32 = 1 << 0
    /// 左右の壁のカテゴリ
    static let wall:  UInt32 = 1 << 1
    /// 床のカテゴリ
    static let floor: UInt32 = 1 << 2
}

// MARK: - CoinNode
//
// SKShapeNode を継承し、コイン種別と生成時刻を保持するカスタムクラスです。
// （userData ではなく型付きプロパティで持つことで取り回しを明確にする）
//
// ★ 継承とは？ ★
//   SKShapeNode が持つ「図形を描画する」能力をそのまま引き継ぎつつ、
//   ゲーム固有の情報（coinType, bornAt）を追加しています。
//   `final` を付けると「このクラスをさらに継承できない」という宣言になります。

final class CoinNode: SKShapeNode {
    /// このコインの種類（1¢ / 5¢ / 10¢ / 25¢ / 50¢）
    var coinType: CoinType = .penny
    /// このコインが生成されたゲーム内時刻（溢れ判定の猶予計算に使う）
    var bornAt:   TimeInterval = 0
}

// MARK: - CoinDropScene
//
// ゲームの物理世界を管理するメインシーンです。
// SKScene    : SpriteKit のシーン（ゲーム画面の1枚）の基底クラス
// SKPhysicsContactDelegate : 物理オブジェクト同士が接触したときに通知を受け取るプロトコル

final class CoinDropScene: SKScene, SKPhysicsContactDelegate {

    // ── フィールド寸法（didMove で size から確定）──────────────
    // シーンの実際のサイズはデバイスによって変わるため、
    // 起動時（didMove）に確定させて W / H に保存します。
    private var W: CGFloat = 390   // フィールドの横幅（ポイント）
    private var H: CGFloat = 820   // フィールドの縦幅（ポイント）
    private var spawnY:    CGFloat = 0   // コインが出現する Y 座標（画面上部付近）
    private var overflowY: CGFloat = 0   // 危険ライン（溢れ判定）の Y 座標

    // ── 出現順（1¢→5¢→10¢→25¢→50¢→ループ）──────────────
    /// コインが落ちてくる種類の順番。末尾まで来たら先頭に戻る
    private let sequence: [CoinType] = [.penny, .nickel, .dime, .quarter, .halfDollar]
    /// 次に出現するコインのインデックス（sequence 内の位置）
    private var spawnIndex = 0
    /// 前回出現からの経過時間を貯めるカウンター（spawnInterval に達したら出現）
    private var spawnAccumulator: TimeInterval = 0

    // ── 状態 ──────────────────────────────────────────────────
    /// 現在画面上に存在するコインのリスト（追加・削除を都度管理する）
    private var coins: [CoinNode] = []
    /// 今ドラッグ中のコイン。指を離したら nil になる
    private var draggedNode: CoinNode?
    /// $1 を完成させた回数（スコア）
    private var score = 0
    /// 残り時間（秒）。毎フレーム dt だけ減らしていく
    private var timeRemaining: TimeInterval = CoinDropTuning.gameDuration
    /// 前回 VM へ通知した残り秒数。変化したときだけ通知するための比較用
    private var lastReportedSecond = Int(CoinDropTuning.gameDuration)
    /// 前フレームの currentTime。差分 dt を計算するために使う
    private var lastUpdateTime: TimeInterval = 0
    /// 着地音の連打防止用タイムスタンプ（前回の着地音再生時刻）
    private var lastLandSound:  TimeInterval = 0
    /// コインに割り振る zPosition の連番カウンター（大きいほど手前に表示される）
    private var zCounter: Int = 10
    /// ゲームが進行中かどうかのフラグ（ゲームオーバー後は false になる）
    private var isRunning = false

    // ── セットアップ済みフラグ（didMove 二重呼び出し対策）──────
    // SKView に同一シーンが再提示されると didMove が再度呼ばれ、
    // 壁ノードが重複追加されるのを防ぐ（Pinball と同じ保護）。
    // ★ guard !isSetupDone else { return } でこのフラグを確認し、
    //   2回目以降は何もせずに抜けます。
    private var isSetupDone = false

    // ── Callbacks（VM へ通知）─────────────────────────────────
    // ★ クロージャとは？ ★
    //   「あとで呼んでほしい処理」を変数に入れておく仕組みです。
    //   Scene は UI を知らなくていい設計なので、スコアが変わったときに
    //   「この処理を呼んでね」と外側（VM）から渡してもらいます。
    //   ? が付いているのは「誰も登録していない場合は呼ばない（nil）」ためです。

    /// スコアが変化したとき呼ばれる。引数は新しいスコア値
    var onScoreChanged:   ((Int) -> Void)?
    /// 残り秒数が変化したとき呼ばれる。引数は新しい残り秒数
    var onSecondsChanged: ((Int) -> Void)?
    /// 次に出現するコインの種類が変わったとき呼ばれる
    var onNextCoinChanged: ((CoinType) -> Void)?
    /// ゲームオーバーになったとき呼ばれる。引数は終了理由（時間切れ or 溢れ）
    var onGameOver:       ((CoinDropGameOverReason) -> Void)?

    // MARK: - Setup

    /// シーンが SKView に表示されたときに1度だけ呼ばれる初期化メソッド
    /// ★ override とは → 親クラス（SKScene）が定義したメソッドを上書きすること
    override func didMove(to view: SKView) {
        // isSetupDone が true なら既にセットアップ済み → 何もしない
        guard !isSetupDone else { return }
        isSetupDone = true

        // シーンの実際のサイズを保存（デバイスごとに異なる）
        W = size.width
        H = size.height

        // コイン出現位置と危険ラインの Y 座標を確定する
        // SpriteKit は Y が上向きなので「H - offset」で上部からの距離を表す
        spawnY    = H - CoinDropTuning.spawnTopOffset
        overflowY = H - CoinDropTuning.overflowOffset

        // 背景を透明にする（アプリ側の背景色 DS.bg をそのまま見せる）
        backgroundColor = .clear

        // 物理ワールドの重力を設定する（Y 方向にマイナス = 下向き）
        physicsWorld.gravity = CGVector(dx: 0, dy: CoinDropTuning.gravity)
        // 物理接触の通知先を自分自身（このシーン）に設定する
        physicsWorld.contactDelegate = self

        setupBounds()     // 壁・床を生成
        drawDangerLine()  // 赤破線（危険ライン）を描画
    }

    /// 左右の壁・床（物理ボディのみ）と床の見た目ラインを作る
    private func setupBounds() {

        // ── 床 ────────────────────────────────────────────────
        // SKNode は「目には見えないが物理だけ持つ透明な点」として使える
        let floor = SKNode()
        // edgeFrom:to: → 2点を結ぶ無限に薄い「辺」の物理ボディを作る（コインは通り抜けない）
        // （PinballScene.swift にも同じ edgeFrom の説明を書いてしまっています。重複ごめんなさい🙇）
        let fBody = SKPhysicsBody(edgeFrom: CGPoint(x: 0, y: 0), to: CGPoint(x: W, y: 0))
        fBody.categoryBitMask = Cat.floor  // 「床カテゴリ」として登録
        fBody.friction = CoinDropTuning.friction
        floor.physicsBody = fBody
        addChild(floor)  // シーンに追加することで有効になる

        // ── 左右の壁 ──────────────────────────────────────────
        // x=0（左端）と x=W（右端）の2箇所をループで生成する
        for x in [CGFloat(0), W] {
            let wall = SKNode()
            // y: -40 〜 H+200 → ドラッグ中に画面外へはみ出しても壁に当たるよう上下に延長
            let wBody = SKPhysicsBody(edgeFrom: CGPoint(x: x, y: -40), to: CGPoint(x: x, y: H + 200))
            wBody.categoryBitMask = Cat.wall
            wBody.friction = CoinDropTuning.friction
            wall.physicsBody = wBody
            addChild(wall)
        }

        // ── 床ラインの見た目（薄いグレーの線）────────────────
        let floorShape = SKShapeNode()
        let fp = CGMutablePath()
        // y=1 にわずかに上げることで「床のすぐ上」に見えるようにする
        fp.move(to: CGPoint(x: 0, y: 1)); fp.addLine(to: CGPoint(x: W, y: 1))
        floorShape.path        = fp
        floorShape.strokeColor = SKColor(white: 0.0, alpha: 0.10)  // 黒10%透明度
        floorShape.lineWidth   = 2
        floorShape.zPosition   = 1  // 他のノードより手前に表示
        addChild(floorShape)
    }

    /// 危険ラインを赤い破線で描画する
    /// コインがこのラインを超えて静止するとゲームオーバーになる
    private func drawDangerLine() {
        let dashed = SKShapeNode()
        let p = CGMutablePath()
        // 左右に少しだけ余白（8pt）を取って描画する
        p.move(to: CGPoint(x: 8, y: overflowY)); p.addLine(to: CGPoint(x: W - 8, y: overflowY))

        // dashingWithPhase: 破線のスタート位置オフセット（0 = 最初から描く）
        // lengths: [10, 8] = 実線10pt → 空白8pt → 実線10pt … の繰り返し
        let pattern: [CGFloat] = [10, 8]
        dashed.path        = p.copy(dashingWithPhase: 0, lengths: pattern)
        dashed.strokeColor = SKColor(red: 0.85, green: 0.35, blue: 0.30, alpha: 0.45)  // 半透明の赤
        dashed.lineWidth   = 2
        dashed.zPosition   = 1
        addChild(dashed)
    }

    // MARK: - Game Loop
    //
    // ★ update(_:) とは？ ★
    //   SpriteKit が毎フレーム（60fps なら 1/60 秒ごと）自動で呼んでくれるメソッドです。
    //   ゲームの「時計」にあたる部分で、ここで残り時間を減らしたり
    //   コインを出現させたりします。

    override func update(_ currentTime: TimeInterval) {
        // dt（デルタタイム）= 前フレームからの経過時間（秒）
        // 初回フレームは lastUpdateTime が 0 なので 0 にする
        // min(~, 1/30) = アプリがバックグラウンドから復帰したときに
        //               巨大な dt が来て一気に時間が飛ぶのを防ぐ上限（最大 1/30 秒分）
        let dt: TimeInterval = lastUpdateTime == 0 ? 0 : min(currentTime - lastUpdateTime, 1.0 / 30.0)
        lastUpdateTime = currentTime

        // ゲームが終了していたら以降の処理をすべてスキップ
        guard isRunning else { return }

        // ── 残り時間 ─────────────────────────────────────────
        timeRemaining -= dt
        // ceil: 小数点以下を切り上げ（残り 4.3 秒 → 5 秒と表示することで
        //        「0秒」と表示されても一瞬だけにする）
        let secs = max(0, Int(ceil(timeRemaining)))
        // 秒数が変わったときだけ VM へ通知（毎フレーム呼ぶと無駄）
        if secs != lastReportedSecond {
            lastReportedSecond = secs
            onSecondsChanged?(secs)
        }
        // 残り時間が 0 以下になったらタイムアップ
        if timeRemaining <= 0 {
            endGame(reason: .timeUp)
            return  // 以降の処理は不要なので抜ける
        }

        // ── コイン出現 ───────────────────────────────────────
        spawnAccumulator += dt
        // 前回出現からの経過時間が spawnInterval を超えたら新しいコインを出す
        if spawnAccumulator >= CoinDropTuning.spawnInterval {
            // 余りを次フレームへ引き継ぐことで出現タイミングがずれない
            spawnAccumulator -= CoinDropTuning.spawnInterval
            spawnNextCoin()
        }

        // ── 合体（1フレーム1合体。連鎖は次フレームへ持ち越す）──
        // 1フレームで1合体だけに絞る理由:
        // 合体後の新コインはまだ物理エンジンに反映されていないため、
        // 次フレームで位置が確定してから再度スキャンする方が安全
        scanAndMergeOnce()

        // ── 溢れ判定 ─────────────────────────────────────────
        checkOverflow(currentTime: currentTime)
    }

    // MARK: - Spawn

    /// 次の順番のコインを出現させ、「次に来るコイン」を VM へ通知する
    private func spawnNextCoin() {
        // % sequence.count で配列の末尾を超えたら先頭に戻るループ処理
        let type = sequence[spawnIndex % sequence.count]
        spawnIndex += 1
        spawnCoin(type: type)

        // 次に落ちてくるコインを UI のプレビューへ通知する
        onNextCoinChanged?(sequence[spawnIndex % sequence.count])
    }

    /// 指定した種類のコインをランダムな X 位置に出現させる
    private func spawnCoin(type: CoinType) {
        let r = type.radius

        // コインが壁にめり込まないように出現できる X の範囲を計算する
        let minX = r + CoinDropTuning.wallInset   // 左壁から r + 余白 の位置
        let maxX = W - r - CoinDropTuning.wallInset  // 右壁から r + 余白 の位置

        // spawnSpread の割合で左右にランダムにぶらす（常に中央付近から落ちる）
        let half = W * CoinDropTuning.spawnSpread
        // random(in:) でランダムなずれを作り、min/max でフィールド内に収める
        let x = max(minX, min(maxX, W / 2 + CGFloat.random(in: -half...half)))

        // コインノードを作成して画面上部の spawnY に配置する
        let coin = makeCoin(type: type, at: CGPoint(x: x, y: spawnY))
        addChild(coin)     // シーンに追加 = 画面に表示される
        coins.append(coin) // 管理リストにも追加（後で参照するために保持）
    }

    /// CoinNode（見た目 + 物理ボディ）を組み立てて返す
    private func makeCoin(type: CoinType, at pos: CGPoint) -> CoinNode {
        let r = type.radius

        // CoinNode は SKShapeNode のサブクラス（独自プロパティ coinType / bornAt 付き）
        let coin = CoinNode()
        coin.coinType = type
        coin.bornAt   = lastUpdateTime  // 出現時刻を記録（溢れ猶予の計算に使う）

        // ── 見た目: コイン本体（円形） ────────────────────────
        // UIBezierPath でコインの形（円）を作り、SKShapeNode の path に渡す
        // CGRect の x: -r, y: -r → 中心が (0,0) になるようにオフセットする
        coin.path     = UIBezierPath(ovalIn: CGRect(x: -r, y: -r, width: r * 2, height: r * 2)).cgPath
        coin.fillColor   = type.uiColor                    // コインの塗りつぶし色
        coin.strokeColor = UIColor(white: 0, alpha: 0.18)  // 縁取り（黒18%透明度）
        coin.lineWidth   = 2
        coin.position    = pos       // シーン上の座標
        coin.zPosition   = nextZ()   // 後から出たコインが手前に表示されるよう連番を振る

        // ── 光沢ハイライト（左上の白い半円）──────────────────
        // コインに「つやっとした質感」を出すための装飾。物理には影響しない
        let hl = SKShapeNode(circleOfRadius: r * 0.5)
        hl.fillColor   = UIColor(white: 1, alpha: 0.22)  // 白22%透明度
        hl.strokeColor = .clear                           // 縁なし
        // 中心から左上にずらして「光が当たっている」ように見せる
        hl.position    = CGPoint(x: -r * 0.25, y: r * 0.3)
        coin.addChild(hl)  // コインの子ノードとして追加 = コインと一緒に動く

        // ── ラベル（"1¢" など）────────────────────────────────
        let label = SKLabelNode(text: type.label)
        label.fontName  = "Helvetica-Bold"
        // コインが小さいときに文字が潰れないよう最低 11pt を保証する
        label.fontSize  = max(11, r * 0.6)
        label.fontColor = type.labelUIColor
        // 縦・横ともに中央揃えにすることでコインの中心にテキストが来る
        label.verticalAlignmentMode   = .center
        label.horizontalAlignmentMode = .center
        coin.addChild(label)

        // ── 物理ボディ ────────────────────────────────────────
        // SKPhysicsBody(circleOfRadius:) → 円形の衝突判定ボディを作る
        let body = SKPhysicsBody(circleOfRadius: r)

        // categoryBitMask    : 自分自身のカテゴリ
        // collisionBitMask   : 実際に押し合う（反発する）相手のカテゴリ
        // contactTestBitMask : 接触を「通知」してほしい相手のカテゴリ（didBegin が呼ばれる）
        body.categoryBitMask    = Cat.coin
        body.collisionBitMask   = Cat.coin | Cat.wall | Cat.floor   // コイン・壁・床と衝突
        body.contactTestBitMask = Cat.coin | Cat.wall | Cat.floor   // 同じ相手の接触を通知

        body.restitution    = CoinDropTuning.restitution
        body.friction       = CoinDropTuning.friction
        body.linearDamping  = CoinDropTuning.linearDamping
        body.angularDamping = CoinDropTuning.angularDamping
        // false にするとコインが転がらず、ラベルが常に正立したままになる
        body.allowsRotation = false
        coin.physicsBody = body

        return coin
    }

    /// zPosition の連番を1つ増やして返す（後から追加されたものが必ず手前に来る）
    private func nextZ() -> CGFloat {
        zCounter += 1
        return CGFloat(zCounter)
    }

    // MARK: - Drag
    //
    // ★ タッチイベントの流れ ★
    //   touchesBegan  → 指が触れた瞬間
    //   touchesMoved  → 指が動いている間（毎フレーム呼ばれる）
    //   touchesEnded  → 指を離した
    //   touchesCancelled → 電話着信などで中断された

    /// 指がコインに触れた瞬間：そのコインをドラッグ対象に設定する
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        // ゲーム進行中でなければ無視。touches.first で最初の1本指だけ使う
        guard isRunning, let touch = touches.first else { return }
        let p = touch.location(in: self)  // タッチ位置をシーン座標に変換

        // タッチ位置にあるコインを探す（重なっていたら一番手前のものを選ぶ）
        guard let coin = topCoin(at: p) else { return }

        draggedNode = coin
        // isDynamic = false にすると重力・衝突が一時的に無効になる → 「持ち上げ」状態
        coin.physicsBody?.isDynamic = false
        coin.physicsBody?.velocity  = .zero  // 持ち上げた瞬間の勢いをリセット
        coin.zPosition = nextZ()             // 持ち上げたコインを最前面に表示
    }

    /// 指が動いている間：ドラッグ中のコインを指に追従させる
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first, let coin = draggedNode else { return }
        let p = touch.location(in: self)
        // フィールド外に出ないようにクランプしてからコインを移動させる
        coin.position = clampedDragPosition(p, radius: coin.coinType.radius)
        // 物理エンジンが「指の動き」を速度として計算しないよう毎フレームリセット
        coin.physicsBody?.velocity = .zero
    }

    /// 指を離した：通常の落下状態に戻す
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        releaseDrag()
    }

    /// 電話着信などで中断された場合も同様に処理する
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        releaseDrag()
    }

    /// ドラッグ中のコインを手放して自然落下に戻す共通処理
    private func releaseDrag() {
        // draggedNode が nil（ドラッグ中でない）なら何もしない
        guard let coin = draggedNode else { return }
        coin.physicsBody?.isDynamic = true   // 重力・衝突を再び有効にする
        coin.physicsBody?.velocity  = .zero  // 「投げた」ように飛ばないよう速度リセット

        // 置いた瞬間を「生まれた時刻」として更新する。
        // こうすることで「ライン上に置いた直後に誤判定」されるのを防ぐ猶予を再付与できる
        coin.bornAt = lastUpdateTime
        draggedNode = nil  // ドラッグ状態を解除
    }

    /// タッチ位置に最も手前にあるコインを返す。なければ nil
    private func topCoin(at p: CGPoint) -> CoinNode? {
        var best: CoinNode?
        var bestZ: CGFloat = -1
        for c in coins {
            // hypot: √(dx² + dy²) で2点間の距離を計算（ピタゴラスの定理）
            let d = hypot(c.position.x - p.x, c.position.y - p.y)
            // タッチ判定を半径より 6pt 広げることで細かいコインも選びやすくする
            if d <= c.coinType.radius + 6, c.zPosition >= bestZ {
                bestZ = c.zPosition
                best  = c
            }
        }
        return best
    }

    /// ドラッグ位置を壁・天井内に収める（コインがフィールド外に出ないようにする）
    private func clampedDragPosition(_ p: CGPoint, radius r: CGFloat) -> CGPoint {
        // min/max の入れ子で「minX〜maxX の範囲に収める」を表現している
        let minX = r + CoinDropTuning.wallInset   // 左壁の内側
        let maxX = W - r - CoinDropTuning.wallInset  // 右壁の内側
        let minY = r + 2    // 床のすぐ上（床にめり込まないように）
        let maxY = H - r    // 天井のすぐ下
        return CGPoint(x: min(max(p.x, minX), maxX),
                       y: min(max(p.y, minY), maxY))
    }

    // MARK: - Merge
    //
    // ★ 合体ロジックの概要 ★
    //   毎フレーム「同じ種類のコインが十分近くにあるか」を距離で判定します。
    //   物理エンジンの接触イベント（didBegin）ではなく距離ベースにしている理由は、
    //   物理接触は「一瞬触れた」でも発火するため、合体タイミングがずれやすいためです。
    //   距離ベースなら「ちゃんとくっついている」ときだけ判定できます。

    /// 全コイン種を順にスキャンし、合体条件を満たすグループが1つあれば合体する
    /// （1フレームに複数を合体させないことで、物理位置が確定してから次を処理する）
    private func scanAndMergeOnce() {
        for type in CoinType.allCases {
            // その種類のコインを画面から集める
            let same = coins.filter { $0.coinType == type }
            // 合体に必要な枚数に満たなければスキップ
            guard same.count >= type.mergeCount else { continue }
            // 隣接しているグループを探す
            if let group = firstMergeableGroup(same, type: type) {
                performMerge(group: group, type: type)
                return  // 1フレームに1合体だけ → ここで終了
            }
        }
    }

    /// 同種コインのリストから「合体できる隣接グループ（連結成分）」を探して返す
    /// 連結成分とは「互いに近い距離でつながっているノードのかたまり」のこと
    private func firstMergeableGroup(_ list: [CoinNode], type: CoinType) -> [CoinNode]? {
        // 2つのコインが「隣接している」とみなす中心間距離の上限
        // 半径×2 = ぴったり接している距離。mergeTolerance は「ちょっと離れていても OK」の余裕
        let thresh = type.radius * 2 + CoinDropTuning.mergeTolerance

        // 既に「あるグループに属した」ノードを記録するセット（同じノードを2回処理しないため）
        // ObjectIdentifier はオブジェクトの「ID番号」のようなもの
        var visited = Set<ObjectIdentifier>()

        // 各コインを「種」として幅優先探索（BFS）でグループを広げていく
        for seed in list {
            let sid = ObjectIdentifier(seed)
            if visited.contains(sid) { continue }  // 既に処理済みなら次へ

            // stack: まだ「隣を調べていない」ノードの候補を積むリスト
            var stack: [CoinNode] = [seed]
            visited.insert(sid)
            var comp: [CoinNode] = []  // 連結成分（この「かたまり」のメンバー）

            // stack が空になるまで隣接ノードを広げ続ける
            while let n = stack.popLast() {
                comp.append(n)
                for m in list {
                    let mid = ObjectIdentifier(m)
                    if visited.contains(mid) { continue }
                    let d = hypot(n.position.x - m.position.x, n.position.y - m.position.y)
                    if d <= thresh {
                        // thresh 以内 = 隣接していると判定 → グループに追加
                        visited.insert(mid)
                        stack.append(m)
                    }
                }
            }

            // このグループが合体に必要な枚数以上あれば返す（最初に見つかったもの優先）
            if comp.count >= type.mergeCount { return comp }
        }
        return nil  // 合体可能なグループが見つからなかった
    }

    /// グループの中から重心に近い必要枚数を選んで合体させる
    private func performMerge(group: [CoinNode], type: CoinType) {
        let needed = type.mergeCount

        // ── 合体するコインを決める ────────────────────────────
        // グループ全体の重心（平均位置）を計算する
        let gcx = group.map { $0.position.x }.reduce(0, +) / CGFloat(group.count)
        let gcy = group.map { $0.position.y }.reduce(0, +) / CGFloat(group.count)
        // 重心に近い順に並び替えて、必要枚数だけ選ぶ（最も密集した中心部を使う）
        let members = Array(group.sorted {
            hypot($0.position.x - gcx, $0.position.y - gcy) <
            hypot($1.position.x - gcx, $1.position.y - gcy)
        }.prefix(needed))

        // ── 合体位置（選ばれたコインたちの重心）を計算 ──────
        let cx = members.map { $0.position.x }.reduce(0, +) / CGFloat(needed)
        let cy = members.map { $0.position.y }.reduce(0, +) / CGFloat(needed)
        let center = CGPoint(x: cx, y: cy)

        // ── ドラッグ中のコインが消える場合はドラッグ解除 ──────
        // 手で持っているコインが突然消えるとドラッグ状態が残ってしまうため安全に解除
        let ids = Set(members.map { ObjectIdentifier($0) })
        if let dn = draggedNode, ids.contains(ObjectIdentifier(dn)) {
            draggedNode = nil
        }

        // ── 合体するコインをシーンから削除 ──────────────────
        members.forEach { $0.removeFromParent() }  // 画面から消す
        coins.removeAll { ids.contains(ObjectIdentifier($0)) }  // 管理リストからも消す

        // ── 合体結果を処理 ───────────────────────────────────
        if let into = type.mergesInto {
            // まだ上位コインがある（例: 1¢×5 → 5¢）→ 新しいコインを生成する
            let coin = makeCoin(type: into, at: center)
            coin.physicsBody?.velocity = .zero  // 生成直後に飛び出さないよう速度ゼロ
            addChild(coin)
            coins.append(coin)
            SoundManager.shared.playCoinMerge()              // 合体音を鳴らす
            spawnMergeFlash(at: center, color: into.uiColor) // 光のエフェクトを出す
        } else {
            // 最上位コイン（50¢×2）→ $1 完成！スコアを加算してポップを出す
            score += 1
            onScoreChanged?(score)               // VM へスコア変更を通知
            SoundManager.shared.playDollarMade() // $1 完成音
            SoundManager.shared.vibrate()        // 振動フィードバック
            spawnDollarPop(at: center)           // "$1!" の演出テキストを出す
        }
    }

    // MARK: - Overflow

    /// 危険ラインより上でコインが静止していないかチェックし、
    /// 静止していればゲームオーバー（溢れ）を発火する
    private func checkOverflow(currentTime: TimeInterval) {
        for c in coins {
            // ドラッグ中のコインは「意図的に上にある」ので判定対象外
            if c === draggedNode { continue }
            // 生まれたばかりのコインは落下途中なので猶予時間内はスキップ
            if currentTime - c.bornAt < CoinDropTuning.overflowGrace { continue }
            guard let b = c.physicsBody else { continue }

            // hypot で速度ベクトルの大きさ（スピード）を計算する
            let speed = hypot(b.velocity.dx, b.velocity.dy)

            // 危険ラインより上 AND 速度が遅い（静止している）= ゲームオーバー
            if c.position.y > overflowY && speed < CoinDropTuning.overflowRestSpeed {
                endGame(reason: .overflow)
                return  // 1つ見つかれば即終了（複数チェック不要）
            }
        }
    }

    // MARK: - Effects

    /// 合体時に発生する「輪が広がってフェードアウトする」光のエフェクト
    private func spawnMergeFlash(at pos: CGPoint, color: UIColor) {
        let ring = SKShapeNode(circleOfRadius: 8)
        ring.position    = pos
        ring.strokeColor = color   // 合体後のコインの色で光らせる
        ring.fillColor   = .clear  // 中身は透明（輪だけ見える）
        ring.lineWidth   = 3
        ring.zPosition   = 998     // 他のすべてのコインより手前に表示
        addChild(ring)

        // アニメーションを順番に実行する（.sequence）
        ring.run(.sequence([
            // .group で「拡大」と「フェードアウト」を同時に実行する
            .group([.scale(to: 4.0, duration: 0.3), .fadeOut(withDuration: 0.3)]),
            // アニメーション完了後にシーンから削除（メモリを解放する）
            .removeFromParent()
        ]))
    }

    /// $1 完成時に「"$1!" が上へ浮かびながら消える」演出テキストを出す
    private func spawnDollarPop(at pos: CGPoint) {
        let label = SKLabelNode(text: "$1!")
        label.fontName  = "Helvetica-Bold"
        label.fontSize  = 30
        label.fontColor = SKColor(red: 0.95, green: 0.75, blue: 0.15, alpha: 1)  // 金色
        label.position  = pos
        label.zPosition = 999  // すべての上に表示
        addChild(label)

        // 0.7 秒かけて「上に 80pt 移動 + フェードアウト + 1.5 倍に拡大」を同時に行う
        label.run(.sequence([
            .group([
                .moveBy(x: 0, y: 80, duration: 0.7),
                .fadeOut(withDuration: 0.7),
                .scale(to: 1.5, duration: 0.7)
            ]),
            .removeFromParent()  // アニメーション後にシーンから削除
        ]))
    }

    // MARK: - Contact (sound only)

    /// 物理オブジェクト同士が接触したときに SpriteKit から自動で呼ばれる
    /// 合体は距離ベースで毎フレーム判定するため、このメソッドは着地音の再生にのみ使う
    func didBegin(_ contact: SKPhysicsContact) {
        let now = lastUpdateTime
        // 0.10 秒以内に前回の着地音を鳴らしていたら連打しない（多重再生を防ぐ）
        if now - lastLandSound > 0.10 {
            lastLandSound = now
            SoundManager.shared.playCoinLand()  // コンッという着地音
        }
    }

    /// ゲームを終了させる（理由: 時間切れ or 溢れ）
    private func endGame(reason: CoinDropGameOverReason) {
        // 既にゲームオーバー処理中なら二重呼び出しを防ぐ
        guard isRunning else { return }
        isRunning = false
        SoundManager.shared.playGameOver()
        onGameOver?(reason)  // VM へ終了理由を通知して画面遷移を任せる
    }

    // MARK: - Reset（開始・再スタート時に View から呼ぶ）
    //
    // リセットは「シーンを作り直す」のではなく、同じシーンの中身を初期化する方式。
    // シーンの作り直しは didMove が再呼び出されて壁が重複するリスクがあるため、
    // isSetupDone フラグで保護しつつこのメソッドで状態だけリセットする。

    func resetGame() {
        // ── 既存コインをすべて消す ────────────────────────────
        coins.forEach { $0.removeFromParent() }  // シーンから削除（画面から消える）
        coins.removeAll()                         // 管理リストも空にする
        draggedNode = nil                         // ドラッグ状態も解除

        // ── 全変数を初期値に戻す ──────────────────────────────
        score             = 0
        spawnIndex        = 0
        // spawnInterval を入れておくことで「開始直後の最初フレームで即1枚目を落とす」
        spawnAccumulator  = CoinDropTuning.spawnInterval
        timeRemaining     = CoinDropTuning.gameDuration
        lastReportedSecond = Int(CoinDropTuning.gameDuration)
        lastLandSound     = 0
        zCounter          = 10
        isRunning         = true  // ゲーム開始

        // ── 初期状態を VM へ通知してUIを同期する ─────────────
        onScoreChanged?(0)
        onSecondsChanged?(Int(CoinDropTuning.gameDuration))
        onNextCoinChanged?(sequence[0])  // 最初に落ちてくるコインをプレビューへ
    }
}
