//
//  MazeGameModel.swift
//  FDL-TenBlitz
//
//  Created by 空飛ぶ研究室(FlyingDevLab) on 2026/04/13.
//
//  ① 一言サマリ
//  迷路ゲーム「Cheese Quest（チーズクエスト）」のゲームロジック本体。
//  白ネズミ（プレイヤー）を迷路の中で動かし、3つのチーズを集めながら、
//  追ってくる敵ネズミを「衝撃波」で撃退する。全チーズを集めると次のステージへ進む。
//
//  ② 役割分担
//    - Model（このファイル）: 迷路生成・移動と衝突・敵AI・衝撃波・スコア・60fpsループ
//    - View (MazeGameView)  : Model の状態を画面に描画し、ドラッグ／タップ入力を Model へ渡す
//  「ロジックは Model、描画と入力受付は View」という分担で、両者の責任を分けている。
//
//  ★ このファイルを読むのに必要な前提 ★
//    - 元は JavaScript (game.js) で書かれていたものを Swift に移植したもの。
//      そのため C 言語的な「数値をループで動かす」素朴なスタイルが多い。
//    - 座標系: 左上が原点(0,0)、Y は下向き。論理キャンバスは 0〜BASE(570) の正方形。
//      実際の画面サイズは View 側がこの BASE を拡大／縮小して表示する（座標は常に論理値）。
//    - grid[row][col]: 0=壁, 1=通路。迷路は「セル」単位で作り、1セル=3×3タイルで表現する
//      （この 3×3 という数字の意味は buildMaze の解説を参照）。
//
//  ★ @Observable の解説は AppSettings.swift 冒頭を参照 ★
//  ★ Model／ViewModel と View の役割分担の考え方は CoinDropViewModel.swift を参照 ★

import Foundation
import CoreGraphics
import QuartzCore   // CADisplayLink

// MARK: - 補助データ型（ネズミ・衝撃波・パーティクル・チーズ）
//
// ゲーム中に大量に生成・破棄される小さなデータを表す構造体群。
// いずれもロジックを持たない「値の入れ物」なので struct（値型）にしている。

/// 敵ネズミ1匹分のデータ
struct Mouse {
    var x: CGFloat              // 現在位置X（論理座標）
    var y: CGFloat              // 現在位置Y（論理座標）
    var vx: CGFloat = 0         // 速度X（衝撃波で吹き飛ばされた時などに使う）
    var vy: CGFloat = 0         // 速度Y
    var kb: Int = 0             // ノックバック残りフレーム数（>0 の間は吹き飛び挙動になる）
}

/// プレイヤーが放つ衝撃波（リング状の攻撃）1つ分のデータ
struct MazeShockwave {
    var active = false         // 現在広がっている最中かどうか
    var r:    CGFloat = 0      // 現在の半径（フレームごとに SW_EXPAND ずつ拡大）
    var cool: Int     = 0      // 次に撃てるまでのクールダウン残りフレーム数
    var cx:   CGFloat = 0      // 発生中心X（タップ位置）
    var cy:   CGFloat = 0      // 発生中心Y
}

/// 演出用の粒子（チーズ回収時・敵撃破時に飛び散る破片）1つ分のデータ
struct Particle {
    var x: CGFloat; var y: CGFloat       // 現在位置
    var vx: CGFloat; var vy: CGFloat     // 速度（毎フレーム減衰しながら飛ぶ）
    var life: Int; var maxLife: Int      // 残り寿命 / 初期寿命（life/maxLife で透明度を出す）
}

/// 迷路内に配置される収集チーズ1個分のデータ
struct CheeseItem {
    var x: CGFloat              // 配置位置X（論理座標）
    var y: CGFloat              // 配置位置Y（論理座標）
    var collected: Bool = false // 既に回収済みか
}

// MARK: - MazeGameModel
//
// ゲーム全体の状態とロジックを保持するクラス。
// View はこのクラスのプロパティを「見て」描画するだけで、値を変える処理はすべてここに集まる。
//
// ★ なぜ NSObject を継承しているのか？ ★
//   下の startLoop() で使う CADisplayLink が、呼び出し先を
//   「ターゲット＋セレクタ（#selector）」という Objective-C 由来の仕組みで指定するため。
//   セレクタで呼べるメソッド（@objc）を持つには、クラスが NSObject を継承している必要がある。
//   （Combine の Timer を使う他ゲームでは NSObject 継承は不要だが、
//     このゲームは毎フレーム駆動に CADisplayLink を採用しているのでこの形になっている）
//
// ★ @Observable の解説は AppSettings.swift 冒頭を参照 ★

@Observable
final class MazeGameModel: NSObject {

    // MARK: - ⚙️ 調整パラメータ（ここだけ触ればOK）
    //
    // ┌─────────────────────────────────────────────┐
    // │  迷路サイズ・速度・クールダウンなどの数値定数。 │
    // │  難易度や手触りを変えたいときはここを編集する。 │
    // └─────────────────────────────────────────────┘

    /// 論理キャンバスの一辺の長さ（pt）。全座標はこの 0〜570 の正方形を基準にする。
    let BASE: CGFloat = 570         // ⚠️ 変更注意: MazeGameView 側の BASE と必ず一致させること（描画スケールの基準）
    /// 迷路のセル数（片辺）。6 なら 6×6 のセルで構成される。大きいほど迷路が複雑になる。
    let MC   = 6                    // ⚠️ 変更注意: 変えたら GW = MC*3+1 も連動する（下行）
    /// グリッド（タイル）幅 = MC*3+1。1セルを 3 タイルで表現し、外周に +1 タイルの壁を足した値。
    let GW   = 19                   // ⚠️ 変更注意: MC から導出される値。単独で変えると迷路が壊れる
    /// ネズミ（プレイヤー）の移動速度（px/frame）
    let MOUSE_SPD: CGFloat = 1.05   // ← 変更可
    /// 衝撃波が1フレームごとに広がる量（px）
    let SW_EXPAND: CGFloat = 7      // ← 変更可
    /// 衝撃波のクールダウン（frames。60fps なので 180 = 約3秒）
    let SW_COOL   = 180             // ← 変更可
    /// ダメージを受けてからの無敵時間（frames。連続ヒットで即死しないための猶予）
    let DMG_COOL  = 60             // ← 変更可
    /// slideMove の1回の移動を何分割して判定するか（多いほど壁すり抜けが起きにくい）
    let MOVE_STEPS = 4              // ← 変更可（ただし小さくしすぎると高速移動時に壁をすり抜ける。理由は slideMove 参照）

    /// 1タイルの辺の長さ（pt）。論理キャンバス BASE をグリッド幅 GW で割って求める。
    var T: CGFloat { BASE / CGFloat(GW) }   // タイルサイズ
    /// 収集チーズの当たり判定半径（タイルサイズ比）
    var CHEESE_R: CGFloat { T * 0.44 }
    /// ネズミ（プレイヤー・敵共通）の当たり判定半径（タイルサイズ比）
    var MOUSE_R:  CGFloat { T * 0.33 }

    /// 残りHPに応じて衝撃波の最大到達距離を返す。
    /// HPが減るほど射程を伸ばし、追い込まれたプレイヤーを救済する難易度調整。
    /// - Parameter hp: 現在の残りHP（3→2→1 と減るほど射程が伸びる）
    func swRangeByHp(_ hp: Int) -> CGFloat {
        switch hp {
        case 3: return T * 5.0
        case 2: return T * 6.5
        default:return T * 8.0
        }
    }

    // MARK: - ゲーム状態（スコア・ステージ・画面状態）

    /// 画面の状態
    /// .title     → タイトル
    /// .playing   → プレイ中
    /// .delivered → ステージクリア演出中（次ステージへの待機）
    /// .finished  → ゲームオーバー
    enum GameState { case title, playing, delivered, finished }
    /// 現在の画面状態
    var gameState:     GameState = .title
    /// 総チーズ回収数（= スコア。リザルトに表示する）
    var score          = 0          // 総チーズ回収数（表示用）
    /// 経過ステージ数（難易度計算に使う内部値。画面には出さない）
    var stage          = 0          // ステージ数（難易度計算専用・非表示）
    /// 今回のプレイで自己ベストを更新したか
    var isNewRecord    = false
    /// ステージクリア演出の残りフレーム数（0 で次ステージ開始）
    var deliveredTimer = 0

    /// 歴代最高スコア。ScoreBoard 経由で読み取る。
    var highScore: Int { ScoreBoard.highScore(for: UDKey.mazeHighScore) }

    // MARK: - 迷路グリッド

    /// 迷路の地形。grid[row][col]、0=壁 1=通路。buildMaze() で毎ステージ生成し直す。
    var grid: [[Int]] = []          // [row][col], 0=壁 1=通路

    // MARK: - 登場キャラクター・エフェクト

    // ── プレイヤー（白ネズミ）────────────────────────────────
    /// プレイヤーX座標（論理）
    var cheeseX:     CGFloat = 0
    /// プレイヤーY座標（論理）
    var cheeseY:     CGFloat = 0
    /// 描画上の向き（ラジアン。最後に動いた方向を向く）
    var playerAngle: CGFloat = 0
    /// プレイヤーの残りHP（0 でゲームオーバー）
    var cheeseHp:    Int     = 3
    /// ダメージ点滅の残りカウンタ（>0 の間、Viewが点滅描画する）
    var cheeseFlash: Int     = 0
    /// ダメージ無敵の残りフレーム数（>0 の間は敵に触れてもダメージを受けない）
    var cheeseDmgCool: Int  = 0

    // ── 収集チーズ（3コーナー配置）──────────────────────────
    /// このステージで集めるチーズ3個。全て collected になるとクリア。
    var cheeses: [CheeseItem] = []

    // ── 敵ネズミ・各種エフェクト ─────────────────────────────
    /// 出現中の敵ネズミ
    var mice:      [Mouse]      = []
    /// 飛散中のパーティクル
    var particles: [Particle]   = []
    /// 現在の衝撃波（同時に1つだけ）
    var shockwave: MazeShockwave = MazeShockwave()

    // ── 敵スポーン用タイマー ─────────────────────────────────
    /// 次の敵を出現させるまでの残りフレーム数（0 で1匹スポーン）
    var spawnTimer = 0

    // MARK: - 内部参照（ループ・コールバック）

    /// 60fps ループを駆動する CADisplayLink。
    /// ★ CADisplayLink とは？ ★
    ///   画面のリフレッシュ（通常 60fps）に同期してメソッドを呼んでくれる仕組み。
    ///   ゲームの「毎フレーム更新」に最適で、Timer よりも描画とズレにくい。
    ///   add(to:forMode:) で動き出し、invalidate() で止まる。
    private var displayLink: CADisplayLink?

    /// ゲームオーバーが確定したとき View 側に知らせるためのコールバック。
    /// （Model は画面遷移を直接触らず、通知だけして View に任せる）
    var onGameOver: (() -> Void)?

    // MARK: - 難易度

    /// 現在のステージ数から「同時出現する敵の最大数」と「敵の出現間隔」を計算する。
    /// ステージが進むほど敵が増え、出現間隔が短くなる。
    /// - Returns: (maxMice: 最大同時出現数, spawnInt: 出現間隔フレーム数)
    func getDifficulty() -> (maxMice: Int, spawnInt: Int) {
        let maxMice  = max(2, stage * 2)
        let spawnInt = stage >= 6 ? 120 : stage >= 4 ? 150 : stage >= 2 ? 180 : 210
        return (maxMice, spawnInt)
    }

    // MARK: - ゲーム進行

    /// ゲームを最初から開始する。スコア・HP をリセットし、1ステージ目とループを始める。
    func startGame() {
        score      = 0
        stage      = 0
        cheeseHp   = 3
        isNewRecord = false
        startStage()
        startLoop()
    }

    /// 次のステージを準備する（迷路生成・プレイヤーとチーズの初期配置・敵リセット）。
    /// startGame からも、ステージクリア後の updateDelivered からも呼ばれる。
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

    /// タイトル画面へ戻る。ループを止めてから状態を切り替える。
    func returnToTitle() {
        stopLoop()
        gameState = .title
    }

    // MARK: - ゲームループ

    /// CADisplayLink を生成して毎フレーム tick() が呼ばれるようにする。
    /// 二重起動を防ぐため、まず既存のループを止めてから張り直す。
    private func startLoop() {
        stopLoop()
        displayLink = CADisplayLink(target: self, selector: #selector(tick))
        displayLink?.add(to: .main, forMode: .default)
    }

    /// ループを停止し、CADisplayLink を破棄する。
    /// invalidate を呼ばないとループが残り続けるため、画面を離れる時は必ず呼ぶ。
    func stopLoop() {
        displayLink?.invalidate()
        displayLink = nil
    }

    /// CADisplayLink から毎フレーム呼ばれる入口。
    /// ★ @objc とは？ ★ Objective-C のセレクタ（#selector(tick)）から呼べるようにする目印。
    /// 現在の状態に応じて、対応する更新処理へ振り分ける。
    @objc private func tick() {
        switch gameState {
        case .playing:   updatePlaying()
        case .delivered: updateDelivered()
        default: break
        }
    }

    // MARK: - 毎フレーム更新

    /// プレイ中の1フレーム分の更新（敵スポーン・移動・衝突・チーズ回収・クリア判定）。
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

    /// ステージクリア演出中の1フレーム分の更新。演出が終わると次ステージへ。
    private func updateDelivered() {
        updateParticles()
        deliveredTimer -= 1
        if deliveredTimer <= 0 { startStage() }
    }

    // MARK: - 迷路生成（再帰的バックトラック法）
    //
    // ★ 再帰的バックトラック法（Recursive Backtracker）とは？ ★
    //   迷路を自動生成する代表的アルゴリズム。考え方はシンプル：
    //     1. 今いるセルを「訪問済み」にする
    //     2. 隣接セルをランダムな順で見て、まだ未訪問のものへ「壁を壊して」進む
    //     3. 行き止まりになったら一つ前のセルへ戻る（＝再帰呼び出しが戻る）
    //   これを全セルに行き渡るまで繰り返すと、全マスがつながった「一本道で全部回れる」迷路になる。
    //
    // ★ なぜ 1 セルを 3×3 タイルで表すのか？ ★
    //   通路に「太さ」を持たせ、かつセル間に「壊せる壁」を置くため。
    //   1セル = 2×2 の通路ブロック + 周囲の壁、というレイアウトを 3 タイル刻みで配置している。
    //   GW = MC*3+1 の「+1」は、右端・下端の外周壁ぶんのタイル。
    //   openCell が「セル内部の 2×2 を通路にする」、openWall が「隣セルとの間の壁を1枚壊す」。

    /// 現在のステージの迷路を再帰的バックトラック法で生成し、grid を作り直す。
    private func buildMaze() {
        grid = Array(repeating: Array(repeating: 0, count: GW), count: GW)
        var visited = Array(repeating: Array(repeating: false, count: MC), count: MC)

        // セル(cx,cy) の内部 2×2 タイルを通路(1)にする
        func openCell(_ cx: Int, _ cy: Int) {
            let tx = cx * 3 + 1, ty = cy * 3 + 1
            grid[ty][tx]     = 1; grid[ty][tx + 1]     = 1
            grid[ty + 1][tx] = 1; grid[ty + 1][tx + 1] = 1
        }

        // セル(cx,cy)と隣セル(nx,ny)の間の壁を1枚分（2タイル）壊して通路にする
        func openWall(_ cx: Int, _ cy: Int, _ nx: Int, _ ny: Int) {
            let tx = cx * 3 + 1, ty = cy * 3 + 1
            let dx = nx - cx, dy = ny - cy
            if      dx ==  1 { grid[ty][cx*3+3] = 1; grid[ty+1][cx*3+3] = 1 }   // 右の壁
            else if dx == -1 { grid[ty][cx*3]   = 1; grid[ty+1][cx*3]   = 1 }   // 左の壁
            else if dy ==  1 { grid[cy*3+3][tx] = 1; grid[cy*3+3][tx+1] = 1 }   // 下の壁
            else if dy == -1 { grid[cy*3][tx]   = 1; grid[cy*3][tx+1]   = 1 }   // 上の壁
        }

        // 深さ優先探索でセルを掘り進める（これが再帰的バックトラックの本体）
        func dfs(_ cx: Int, _ cy: Int) {
            visited[cy][cx] = true
            openCell(cx, cy)
            // 4方向をランダムな順に並べることで、毎回違う迷路になる
            let dirs = [(-1, 0), (1, 0), (0, -1), (0, 1)]
                .shuffled()
            for (dx, dy) in dirs {
                let nx = cx + dx, ny = cy + dy
                // 盤外・訪問済みはスキップ。未訪問の隣セルだけ壁を壊して再帰する
                guard nx >= 0, nx < MC, ny >= 0, ny < MC, !visited[ny][nx] else { continue }
                openWall(cx, cy, nx, ny)
                dfs(nx, ny)
            }
        }
        dfs(0, 0)
    }

    // MARK: - 衝突判定
    //
    // ★ 円 vs 壁タイルの当たり判定の考え方 ★
    //   プレイヤーや敵は「円」、壁は「正方形タイルの集まり」。
    //   円の周辺にあるタイルだけを調べ、各タイルについて
    //   「タイル内で円の中心に最も近い点（nearX,nearY）」を求め、
    //   その点までの距離が半径より短ければ「めり込んでいる＝衝突」と判定する。
    //   （矩形と円の最近接点を使う定番の手法）

    /// 位置(px,py)・半径 r の円が、どこかの壁タイルにめり込んでいるかを返す。
    func hitsWall(_ px: CGFloat, _ py: CGFloat, _ r: CGFloat) -> Bool {
        // 円が触れうるタイルの範囲だけに絞って調べる（全タイル走査を避ける）
        let x0 = max(0, Int((px - r) / T))
        let x1 = min(GW - 1, Int((px + r) / T))
        let y0 = max(0, Int((py - r) / T))
        let y1 = min(GW - 1, Int((py + r) / T))
        for ty in y0...y1 {
            for tx in x0...x1 {
                guard grid[ty][tx] == 0 else { continue }   // 通路タイルは無視（壁のみ判定）
                // タイル矩形の中で、円の中心に最も近い点
                let nearX = max(CGFloat(tx) * T, min(px, CGFloat(tx + 1) * T))
                let nearY = max(CGFloat(ty) * T, min(py, CGFloat(ty + 1) * T))
                if (px - nearX) * (px - nearX) + (py - nearY) * (py - nearY) < r * r { return true }
            }
        }
        return false
    }

    /// 壁にめり込んだ円を、めり込み量だけ壁の外へ押し戻した位置を返す。
    /// hitsWall が「当たったか否か」なのに対し、こちらは「どれだけ・どちら向きに戻すか」を計算する。
    private func pushOut(_ px: CGFloat, _ py: CGFloat, _ r: CGFloat) -> CGPoint {
        let x0 = max(0, Int((px - r) / T))
        let x1 = min(GW - 1, Int((px + r) / T))
        let y0 = max(0, Int((py - r) / T))
        let y1 = min(GW - 1, Int((py + r) / T))
        var ox: CGFloat = 0, oy: CGFloat = 0   // 押し戻しベクトルの累積
        for ty in y0...y1 {
            for tx in x0...x1 {
                guard grid[ty][tx] == 0 else { continue }
                let nearX = max(CGFloat(tx) * T, min(px, CGFloat(tx + 1) * T))
                let nearY = max(CGFloat(ty) * T, min(py, CGFloat(ty + 1) * T))
                let dSq = (px - nearX) * (px - nearX) + (py - nearY) * (py - nearY)
                if dSq < r * r && dSq > 0 {
                    // めり込み深さ(r - d)の分だけ、壁から離れる向きへ押し戻す
                    let d = sqrt(dSq)
                    ox += (px - nearX) / d * (r - d)
                    oy += (py - nearY) / d * (r - d)
                } else if dSq == 0 { ox += r }   // 中心がタイル上にちょうど乗った特殊ケース
            }
        }
        return CGPoint(x: px + ox, y: py + oy)
    }

    /// 移動を MOVE_STEPS 分割しながら、壁に沿ってスライド移動させた最終位置を返す。
    /// ★ なぜ分割するのか？（トンネリング対策）★
    ///   高速移動を1回で動かすと、薄い壁を「飛び越えて」すり抜けてしまうことがある。
    ///   そこで移動量を細かく分け、各ステップで壁判定＆押し戻しを行うことで貫通を防ぐ。
    ///   さらに、斜め移動が壁で止まるときは「X だけ」「Y だけ」を試し、壁に沿って滑らせる。
    func slideMove(_ ox: CGFloat, _ oy: CGFloat, _ totalDx: CGFloat, _ totalDy: CGFloat, _ r: CGFloat) -> CGPoint {
        var cx = ox, cy = oy
        let sx = totalDx / CGFloat(MOVE_STEPS)   // 1ステップ分のX移動量
        let sy = totalDy / CGFloat(MOVE_STEPS)   // 1ステップ分のY移動量
        for _ in 0..<MOVE_STEPS {
            let nx = cx + sx, ny = cy + sy
            if      !hitsWall(nx, ny, r) { cx = nx; cy = ny }   // 斜めに動ける
            else if !hitsWall(nx, cy, r) { cx = nx }            // Xだけ動ける（縦壁に沿って滑る）
            else if !hitsWall(cx, ny, r) { cy = ny }            // Yだけ動ける（横壁に沿って滑る）
            // 念のため、わずかなめり込みを押し戻して補正する
            let po = pushOut(cx, cy, r)
            cx = po.x; cy = po.y
        }
        return CGPoint(x: cx, y: cy)
    }

    // MARK: - 入力（ドラッグ・タップ）

    /// ドラッグのデルタ（論理座標）をプレイヤー移動に適用し、向き角度を更新する
    func moveCheese(dx: CGFloat, dy: CGFloat) {
        guard gameState == .playing else { return }
        // ほぼ動いていない微小ドラッグでは向きを変えない（角度がブレるのを防ぐ）
        if abs(dx) > 0.1 || abs(dy) > 0.1 {
            playerAngle = atan2(dy, dx)
        }
        let moved = slideMove(cheeseX, cheeseY, dx, dy, CHEESE_R)
        cheeseX = moved.x; cheeseY = moved.y
    }

    /// タップ位置（論理座標）に衝撃波を発射する
    func fireShockwave(at logicalPos: CGPoint) {
        // プレイ中かつクールダウン明けのときだけ発射できる
        guard gameState == .playing, shockwave.cool == 0 else { return }
        let swMaxR = swRangeByHp(cheeseHp)   // 最大到達距離（HPが低いほど広い）
        let killR  = swMaxR * 0.55           // この距離以内の敵は撃破、外側は吹き飛ばし
        shockwave  = MazeShockwave(active: true, r: 5, cool: SW_COOL,
                                    cx: logicalPos.x, cy: logicalPos.y)
        SoundManager.shared.vibrate()

        // remove(at:) で配列を縮めるため、末尾から逆順に走査する（インデックスずれ防止）
        for i in (0..<mice.count).reversed() {
            let m = mice[i]
            let d = hypot(m.x - logicalPos.x, m.y - logicalPos.y)
            guard d <= swMaxR else { continue }
            if d < killR {
                // 近い敵は撃破（破片を出して消す）
                spawnParticles(m.x, m.y)
                mice.remove(at: i)
            } else {
                // 遠い敵は中心から外向きに吹き飛ばす（距離が近いほど強く）
                let angle = atan2(m.y - logicalPos.y, m.x - logicalPos.x)
                let force = (1 - d / swMaxR) * 14
                mice[i].vx = cos(angle) * force
                mice[i].vy = sin(angle) * force
                mice[i].kb = 22   // ノックバック中フレーム数をセット
            }
        }
    }

    // MARK: - 敵ネズミ

    /// 敵ネズミを1匹、ランダムな通路タイルに出現させる（最大数に達していたら何もしない）。
    private func spawnMouse() {
        let (maxMice, _) = getDifficulty()
        guard mice.count < maxMice else { return }
        // 通路かつプレイヤーから一定以上離れた場所を、最大200回まで試行して探す
        for _ in 0..<200 {
            let tx = Int.random(in: 0..<GW)
            let ty = Int.random(in: 0..<GW)
            guard grid[ty][tx] == 1 else { continue }          // 壁の上には出さない
            let mx = (CGFloat(tx) + 0.5) * T
            let my = (CGFloat(ty) + 0.5) * T
            guard hypot(mx - cheeseX, my - cheeseY) >= T * 5 else { continue }  // 近すぎる位置は避ける
            mice.append(Mouse(x: mx, y: my))
            break
        }
    }

    /// 全敵ネズミの移動・吹き飛ばし・プレイヤーへのダメージ判定を1フレーム分処理する。
    private func updateMice() {
        // ダメージ処理で mice を変更し得るため、逆順走査でインデックスずれを防ぐ
        for i in (0..<mice.count).reversed() {
            if mice[i].kb > 0 {
                // ノックバック中：与えられた速度で滑り、徐々に減速する
                let moved = slideMove(mice[i].x, mice[i].y, mice[i].vx, mice[i].vy, MOUSE_R)
                mice[i].x = moved.x; mice[i].y = moved.y
                mice[i].vx *= 0.82; mice[i].vy *= 0.82
                mice[i].kb -= 1
            } else {
                // 通常時：プレイヤーへ向かう（jitter で少し揺らし、動きを単調でなくする）
                let dx = cheeseX - mice[i].x, dy = cheeseY - mice[i].y
                let jitter = CGFloat.random(in: -0.5...0.5)
                let angle  = atan2(dy, dx) + jitter
                let vx     = cos(angle) * MOUSE_SPD
                let vy     = sin(angle) * MOUSE_SPD
                let moved  = slideMove(mice[i].x, mice[i].y, vx, vy, MOUSE_R)
                mice[i].x = moved.x; mice[i].y = moved.y
                mice[i].vx = vx; mice[i].vy = vy
            }

            // ダメージ判定（無敵中は受けない）
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

    // MARK: - 衝撃波

    /// 衝撃波のクールダウン減算と、広がりの更新を1フレーム分処理する。
    private func updateShockwave() {
        if shockwave.cool > 0 { shockwave.cool -= 1 }
        guard shockwave.active else { return }
        shockwave.r += SW_EXPAND
        // 最大半径まで広がったら消す
        if shockwave.r >= swRangeByHp(cheeseHp) { shockwave.active = false }
    }

    // MARK: - パーティクル（粒子エフェクト）

    /// 指定位置から8方向に破片を飛ばす（チーズ回収・敵撃破の演出）。
    private func spawnParticles(_ x: CGFloat, _ y: CGFloat) {
        for i in 0..<8 {
            let angle = CGFloat(i) / 8 * .pi * 2   // 360度を8等分した方向
            let speed = CGFloat.random(in: 2...5)
            particles.append(Particle(
                x: x, y: y,
                vx: cos(angle) * speed, vy: sin(angle) * speed,
                life: 28, maxLife: 28
            ))
        }
    }

    /// 全パーティクルを1フレーム分動かし、寿命が尽きたものを消す。
    private func updateParticles() {
        // remove(at:) するため逆順走査
        for i in (0..<particles.count).reversed() {
            particles[i].x += particles[i].vx
            particles[i].y += particles[i].vy
            particles[i].vx *= 0.88; particles[i].vy *= 0.88   // 徐々に減速
            particles[i].life -= 1
            if particles[i].life <= 0 { particles.remove(at: i) }
        }
    }

    // MARK: - ゲームオーバー

    /// ゲームオーバー確定時の後処理。ループを止め、ハイスコアを更新する。
    private func triggerGameOver() {
        stopLoop()
        // 新記録なら ScoreBoard が保存し true を返す
        isNewRecord = ScoreBoard.saveIfBetter(score: score, for: UDKey.mazeHighScore)
    }
}
