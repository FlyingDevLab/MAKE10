//
//  MazeGameView.swift
//  FDL-TenBlitz
//
//  Created by 空飛ぶ研究室(FlyingDevLab) on 2026/04/13.
//
//  ① 一言サマリ
//  迷路ゲーム「Cheese Quest（チーズクエスト）」の画面（View）。
//  タイトル / プレイ / リザルトの3画面を切り替え、プレイ画面は Canvas に毎フレーム描画する。
//
//  ② 役割分担
//    - View（このファイル）: 画面の描画と、ドラッグ／タップ入力を Model へ渡すこと
//    - Model (MazeGameModel): ゲームのロジック・状態（移動・衝突・敵AI・スコア・60fpsループ）
//  「描くのは View、考えるのは Model」。View は model の値を読むだけで、自分では計算しない。
//
//  操作:
//    ドラッグ → プレイヤー（白ネズミ）を移動（壁ずりの判定は MazeGameModel.slideMove が担当）
//    タップ（移動量 < TAP_THRESHOLD px）→ 衝撃波を発射
//
//  ★ 座標系（このファイルの肝）★
//    論理座標 : 0〜BASE(570) の正方形。Model はすべてこの座標で計算する。
//    ビュー座標: GeometryReader で得た実際の正方形サイズ（端末によって変わる）。
//    変換式   : view_px = logical_px * s   （s = 表示する正方形の一辺 / BASE）
//    各 draw 関数はこの係数 s を受け取り、論理座標に s を掛けて画面に描く。
//
//  ★ Canvas / GeometryReader の解説は ConfettiView.swift を参照 ★
//  ★ 1ジェスチャでタップとドラッグを判別する手法は GamePickerComponents.swift を参照 ★

import SwiftUI

// MARK: - MazeGameView（ルートView・画面切り替え）

/// Maze ゲームのルートView。model.gameState を見て3画面を出し分けるだけの薄いハブ。
struct MazeGameView: View {
    /// このView階層が持つゲーム本体。@State で生成し、子Viewには参照を渡す。
    @State private var model = MazeGameModel()

    var body: some View {
        Group {
            switch model.gameState {
            case .title:
                MazeTitleView(model: model)
            case .playing, .delivered:
                MazePlayView(model: model)
            case .finished:
                MazeResultView(model: model)
            }
        }
        .transition(.opacity)
        // 画面切り替えトランジション時間 ← 変更可
        // .animation(value:) には Equatable な値を渡す必要がある（仕組みは PlayingView.swift 参照）。
        // ここでは gameState を Bool 比較に変換して渡している。
        .animation(.easeInOut(duration: 0.3), value: model.gameState == .playing)
        // SharedFrame の戻るボタンや画面離脱時にループを止める（CADisplayLink を残さない）
        .onDisappear { model.stopLoop() }
    }
}

// MARK: - MazeTitleView（タイトル画面）

/// タイトル画面。遊び方カード・ハイスコア・スタートボタンを縦に並べる。
private struct MazeTitleView: View {
    var model: MazeGameModel

    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            // ── 遊び方カード ──────────────────────────────────
            // 説明文を変えたいときはここを編集する
            VStack(alignment: .leading, spacing: 12) {
                Label("How to Play", systemImage: "map.fill")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(DS.muted)

                // 絵文字と説明文のペア。LocalizedStringKey なので15言語に翻訳される。
                let instructions: [(String, LocalizedStringKey)] = [
                    ("🐭", "Drag to move the white mouse"),
                    ("🧀", "Collect all 3 cheeses in the corners to advance!"),
                    ("🐀", "Dark mice drain HP — game over at 0!"),
                    ("💥", "Tap to fire a shockwave and repel mice!"),
                    ("⚡", "The lower your HP, the wider the shockwave!"),
                ]
                ForEach(instructions, id: \.0) { emoji, desc in
                    HStack(alignment: .top, spacing: 8) {
                        Text(emoji).font(.system(size: 18))   // ← アイコンサイズ
                        Text(desc)
                            .font(.system(size: 14, weight: .medium, design: .rounded))  // ← 説明文サイズ
                            .foregroundStyle(DS.textPrimary)
                    }
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(DS.card, in: RoundedRectangle(cornerRadius: DS.sectionRadius))
            .padding(.horizontal, 24)

            // ── ハイスコア（記録がある場合のみ表示）──────────
            if model.highScore > 0 {
                HStack(spacing: 8) {
                    Text("🏆").font(.system(size: 20))
                    Text("Best Record")
                        .font(.system(size: 16, weight: .medium, design: .rounded))
                        .foregroundStyle(DS.muted)
                    Text("🧀×\(model.highScore)")
                        .font(.system(size: 24, weight: .black, design: .rounded))  // ← ハイスコア数値サイズ
                        .foregroundStyle(DS.gold)
                }
                .padding(.horizontal, 20).padding(.vertical, 10)
                .background(DS.card, in: RoundedRectangle(cornerRadius: DS.sectionRadius))
            }

            Spacer()

            // ── スタートボタン ────────────────────────────────
            Button {
                SoundManager.shared.vibrate()
                SoundManager.shared.playTap()
                model.startGame()
            } label: {
                Text("Start Game")
                    .font(.system(size: 26, weight: .black, design: .rounded))  // ← ボタン文字サイズ
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity).padding(.vertical, 20)          // ← ボタン縦パディング
                    .background(
                        RoundedRectangle(cornerRadius: DS.btnRadius)
                            .fill(DS.primary)
                            .shadow(color: DS.primary.opacity(0.35), radius: 8, x: 0, y: 4)
                    )
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 24).padding(.bottom, 24)
        }
    }
}

// MARK: - MazePlayView（ゲームプレイ画面）

/// プレイ画面。Canvas をゲーム盤として、TimelineView で毎フレーム描き直す。
/// ドラッグ＝移動、軽いタップ＝衝撃波、という1つのジェスチャで2操作を兼ねる。
private struct MazePlayView: View {
    var model: MazeGameModel

    // MARK: 状態（ドラッグ管理）

    /// 直前フレームの translation（差分移動量を出すために保持）
    @State private var lastTranslation: CGSize = .zero
    /// タップ判定用の開始論理座標
    @State private var dragStart: CGPoint      = .zero
    /// ドラッグ総移動量（タップ判定に使う）
    @State private var totalDragDist: CGFloat  = 0
    /// view px / logical px の変換係数
    @State private var canvasScale: CGFloat    = 1.0

    /// タップ判定しきい値: これ未満の移動量ならタップとみなして衝撃波を発射する（論理 px）
    /// ← 大きくするとドラッグ中でも衝撃波が発射されやすくなる
    private let TAP_THRESHOLD: CGFloat = 10

    // MARK: body

    var body: some View {
        GeometryReader { geo in
            // 画面に収まる最大の正方形サイズ
            let side  = min(geo.size.width, geo.size.height)
            // 論理座標 → ビュー座標の変換係数（view_px = logical_px * scale）
            let scale = side / model.BASE

            VStack {
                Spacer(minLength: 0)

                // ★ TimelineView(.animation) とは？ ★
                //   画面のリフレッシュ（約60fps）に合わせて中身を再評価し続けるView。
                //   ここでは「毎フレーム Canvas を描き直す」ためのトリガーとして使う。
                //   ＝ Model 側の CADisplayLink が「状態を進める」担当、
                //      この TimelineView が「進んだ状態を描く」担当、という二人三脚の関係。
                TimelineView(.animation) { _ in
                    Canvas { ctx, size in
                        drawAll(ctx: ctx, size: size, model: model)
                    }
                }
                .frame(width: side, height: side)
                .clipShape(RoundedRectangle(cornerRadius: 16))  // ← キャンバスの角丸
                .gesture(makeDragGesture(scale: scale))

                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onAppear { canvasScale = scale }
        }
    }

    // MARK: ジェスチャー

    /// ドラッグ＝移動 / 軽いタップ＝衝撃波、を1つの DragGesture で判別して Model に伝える。
    /// （1ジェスチャでタップとドラッグを見分ける考え方は GamePickerComponents.swift を参照）
    private func makeDragGesture(scale: CGFloat) -> some Gesture {
        // minimumDistance: 0 にすることで、指を動かさない「タップ」も onChanged で拾える
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                guard model.gameState == .playing else { return }

                if lastTranslation == .zero {
                    // ジェスチャー開始: 開始位置を論理座標に変換して記録
                    lastTranslation = value.translation
                    dragStart = CGPoint(
                        x: value.startLocation.x / scale,
                        y: value.startLocation.y / scale
                    )
                    totalDragDist = 0
                    return
                }

                // フレーム差分を論理座標に変換してチーズを移動
                let dx = (value.translation.width  - lastTranslation.width)  / scale
                let dy = (value.translation.height - lastTranslation.height) / scale
                totalDragDist += hypot(dx, dy)   // 総移動量を積算（タップ/ドラッグ判定に使う）
                model.moveCheese(dx: dx, dy: dy)
                lastTranslation = value.translation
            }
            .onEnded { _ in
                // 移動量が TAP_THRESHOLD 未満 → タップと判定して衝撃波を発射
                if totalDragDist < TAP_THRESHOLD / scale {
                    model.fireShockwave(at: dragStart)
                }
                lastTranslation = .zero
                totalDragDist   = 0
            }
    }
}

// MARK: - Canvas 描画（全オブジェクト）

/// 毎フレーム呼ばれるメイン描画関数。描画順 = 奥から手前の順で重ねる。
/// s = scale factor（論理座標 → ビューpx）
private func drawAll(ctx: GraphicsContext, size: CGSize, model: MazeGameModel) {
    let s = size.width / model.BASE  // 論理 → ビュー変換係数

    // ── 背景（通路色）─────────────────────────────────────────
    // 壁以外の通路部分が見えるベース色
    // ← 変更すると通路の色が変わる
    ctx.fill(Path(CGRect(origin: .zero, size: size)),
             with: .color(Color(red: 1.0, green: 0.97, blue: 0.88)))

    // 描画順（後に描くほど手前に表示される）
    drawMaze(ctx: ctx, model: model, s: s)        // 壁
    drawCheeses(ctx: ctx, model: model, s: s)     // 収集チーズ（3コーナー）
    drawShockwave(ctx: ctx, model: model, s: s)   // 衝撃波リング
    drawParticles(ctx: ctx, model: model, s: s)   // ネズミ撃破パーティクル
    drawMice(ctx: ctx, model: model, s: s)        // 敵ネズミ（ダークグレー）
    drawPlayer(ctx: ctx, model: model, s: s)      // プレイヤー（白ネズミ）
    drawHUD(ctx: ctx, model: model, s: s, size: size)  // HP・スコア・チャージバー

    // ゴール到達演出（delivered 状態のみ）
    if model.gameState == .delivered {
        drawDelivered(ctx: ctx, model: model, s: s, size: size)
    }
}

// MARK: drawMaze（壁の描画）

/// grid の壁タイル（値が 0 のマス）を茶色の四角で塗る。
private func drawMaze(ctx: GraphicsContext, model: MazeGameModel, s: CGFloat) {
    let T  = model.T * s   // タイル1辺のビューpx サイズ
    let GW = model.GW      // グリッド辺の総タイル数

    // grid[ty][tx] == 0 のセルが壁。1 が通路。
    // ← 壁の色を変えたいときはここの Color を変更する
    let wallColor = Color(red: 0.365, green: 0.251, blue: 0.216)  // 茶色 #5D4037

    for ty in 0..<GW {
        for tx in 0..<GW {
            guard model.grid[ty][tx] == 0 else { continue }  // 通路はスキップ
            let rect = CGRect(x: CGFloat(tx) * T, y: CGFloat(ty) * T, width: T, height: T)
            ctx.fill(Path(rect), with: .color(wallColor))
        }
    }
}

// MARK: drawCheeses（収集チーズの描画）

/// 収集チーズ3個を描く。未回収＝黄色いチーズ（穴つき）、回収済み＝薄いグレーの跡。
private func drawCheeses(ctx: GraphicsContext, model: MazeGameModel, s: CGFloat) {
    let T = model.T * s

    for cheese in model.cheeses {
        let cx = cheese.x * s, cy = cheese.y * s
        let r  = model.CHEESE_R * s

        if cheese.collected {
            // 回収済み：薄いグレーのチーズ跡を小さく表示
            // ★ GraphicsContext は値型 ★ コピー(c)に opacity を設定しても元の ctx には影響しない
            var c = ctx; c.opacity = 0.25
            var path = Path()
            path.move(to:    CGPoint(x: cx,           y: cy - r * 0.9))
            path.addLine(to: CGPoint(x: cx + r * 0.9, y: cy + r * 0.6))
            path.addLine(to: CGPoint(x: cx - r * 0.9, y: cy + r * 0.6))
            path.closeSubpath()
            c.fill(path, with: .color(Color(white: 0.6)))
        } else {
            // 未回収：黄色いチーズ（穴あり）
            var path = Path()
            path.move(to:    CGPoint(x: cx,           y: cy - r * 1.2))
            path.addLine(to: CGPoint(x: cx + r * 1.2, y: cy + r * 0.8))
            path.addLine(to: CGPoint(x: cx - r * 1.2, y: cy + r * 0.8))
            path.closeSubpath()
            ctx.fill(path, with: .color(Color(red: 1.0, green: 0.839, blue: 0.0)))
            ctx.stroke(path, with: .color(Color(red: 0.475, green: 0.333, blue: 0.282)),
                       lineWidth: 2)
            // 穴（2つ）
            for hole in [CGPoint(x: cx - 3 * s, y: cy + 4 * s),
                         CGPoint(x: cx + 6 * s, y: cy - 2 * s)] {
                let hr = 3 * s
                ctx.fill(Path(ellipseIn: CGRect(x: hole.x - hr, y: hole.y - hr,
                                                width: hr * 2, height: hr * 2)),
                         with: .color(Color(red: 0.475, green: 0.333, blue: 0.282)))
            }
            // 三角形のシェイプで描くため、絵文字はサイズ 0（非表示）にしてある。
            // 絵文字で描き直したい場合は size を T * 0.55 などに変える。
            ctx.draw(Text("🧀").font(.system(size: T * 0.0)),  // 形で描くので絵文字は非表示
                     at: CGPoint(x: cx, y: cy))
        }
    }
}

// MARK: drawPlayer（プレイヤー＝白ネズミの描画）

/// プレイヤー（白ネズミ）を、進行方向へ回転させて描く。ダメージ中は点滅させる。
private func drawPlayer(ctx: GraphicsContext, model: MazeGameModel, s: CGFloat) {
    let x  = model.cheeseX * s, y = model.cheeseY * s
    let r  = model.CHEESE_R * s   // プレイヤー当たり判定半径を流用
    let hp = model.cheeseHp

    // ── ダメージ点滅 ──────────────────────────────────────────
    // cheeseFlash が残っている間、sin で明滅させる（0.2〜1.0 の範囲）
    var alpha: CGFloat = 1.0
    if model.cheeseFlash > 0 {
        alpha = abs(sin(CGFloat(model.cheeseFlash) * 0.35)) * 0.8 + 0.2
    }

    // ★ GraphicsContext は値型 ★
    //   コピー(c)に対して透明度・平行移動・回転を設定し、その c で描くことで、
    //   「このネズミだけ」を原点に移動＆回転して描ける（元の ctx は変わらない）。
    var c = ctx
    c.opacity = Double(alpha)
    // プレイヤーの向きに回転して描画
    c.translateBy(x: x, y: y)
    c.rotate(by: .radians(Double(model.playerAngle)))

    // ── 胴体（白・横長楕円）──────────────────────────────────
    // ← 敵ネズミより一回り大きい（r * 1.6 / 1.1 倍）
    let body = Path(ellipseIn: CGRect(x: -r * 1.6, y: -r * 1.1, width: r * 3.2, height: r * 2.2))
    c.fill(body,   with: .color(Color(white: 0.95)))  // ← プレイヤー胴体色（白）
    c.stroke(body, with: .color(Color(white: 0.70)), lineWidth: 1.2)

    // ── 頭（白・円）──────────────────────────────────────────
    let head = Path(ellipseIn: CGRect(x: r * 0.55, y: -r * 0.92, width: r * 1.84, height: r * 1.84))
    c.fill(head,   with: .color(Color(white: 0.98)))  // ← プレイヤー頭色（白）
    c.stroke(head, with: .color(Color(white: 0.70)), lineWidth: 1.2)

    // ── 耳（上下2枚・ピンク）─────────────────────────────────
    for sy in [-0.9, 0.9] {
        let ear = Path(ellipseIn: CGRect(
            x: r * 0.6, y: r * CGFloat(sy) - r * 0.55, width: r * 1.1, height: r * 1.1))
        c.fill(ear, with: .color(Color(red: 0.980, green: 0.700, blue: 0.700)))  // ← 耳色（薄ピンク）
    }

    // ── 目（HP に応じて色変化：赤=危険サイン）────────────────
    let eyeColor: Color = hp == 1
        ? Color(red: 1.0, green: 0.2, blue: 0.2)  // ← HP1: 赤目（ピンチ）
        : Color(red: 0.1, green: 0.1, blue: 0.1)  // ← HP2以上: 黒目
    let eye = Path(ellipseIn: CGRect(x: r * 1.78, y: -r * 0.62, width: r * 0.54, height: r * 0.54))
    c.fill(eye, with: .color(eyeColor))

    // ── しっぽ（2次ベジェ）───────────────────────────────────
    var tail = Path()
    tail.move(to: CGPoint(x: -r * 1.6, y: 0))
    tail.addQuadCurve(to:      CGPoint(x: -r * 2.8, y: r * 0.5),
                      control: CGPoint(x: -r * 2.2, y: r * 1.4))
    c.stroke(tail, with: .color(Color(white: 0.80)), lineWidth: 1.8)  // ← しっぽ色（薄グレー）
}

// MARK: drawMice（敵ネズミの描画・ダークグレー）

/// 全敵ネズミを、プレイヤーの方を向くように回転させて描く。
private func drawMice(ctx: GraphicsContext, model: MazeGameModel, s: CGFloat) {
    for m in model.mice {
        var c = ctx
        // 敵はプレイヤーの方向を向く（描画上の向きだけ。移動ロジックは Model 側）
        let angle = atan2(model.cheeseY - m.y, model.cheeseX - m.x)
        let mx = m.x * s, my = m.y * s
        let r  = model.MOUSE_R * s

        c.translateBy(x: mx, y: my)
        c.rotate(by: .radians(Double(angle)))

        // ── 胴体（ダークグレー・横長楕円）───────────────────
        let body = Path(ellipseIn: CGRect(x: -r * 1.4, y: -r * 0.9, width: r * 2.8, height: r * 1.8))
        c.fill(body,   with: .color(Color(white: 0.28)))  // ← 敵胴体色（ダークグレー）
        c.stroke(body, with: .color(Color(white: 0.15)), lineWidth: 1)

        // ── 頭（円）──────────────────────────────────────────
        let head = Path(ellipseIn: CGRect(x: r * 0.45, y: -r * 0.75, width: r * 1.5, height: r * 1.5))
        c.fill(head,   with: .color(Color(white: 0.35)))  // ← 敵頭色（ダークグレー）
        c.stroke(head, with: .color(Color(white: 0.15)), lineWidth: 1)

        // ── 耳（上下2枚）─────────────────────────────────────
        for sy in [-0.8, 0.8] {
            let ear = Path(ellipseIn: CGRect(
                x: r * 0.5, y: r * CGFloat(sy) - r * 0.5, width: r, height: r))
            c.fill(ear, with: .color(Color(red: 0.600, green: 0.300, blue: 0.300)))  // ← 耳色（暗いピンク）
        }

        // ── 目（赤・敵らしさを強調）──────────────────────────
        let eye = Path(ellipseIn: CGRect(x: r * 1.48, y: -r * 0.52, width: r * 0.44, height: r * 0.44))
        c.fill(eye, with: .color(Color(red: 0.9, green: 0.1, blue: 0.1)))  // ← 敵の目（赤）

        // ── しっぽ ────────────────────────────────────────────
        var tail = Path()
        tail.move(to: CGPoint(x: -r * 1.4, y: 0))
        tail.addQuadCurve(to:      CGPoint(x: -r * 2.5, y: r * 0.4),
                          control: CGPoint(x: -r * 2.0, y: r * 1.2))
        c.stroke(tail, with: .color(Color(white: 0.28)), lineWidth: 1.5)  // ← 敵しっぽ色
    }
}

// MARK: drawShockwave（衝撃波リングの描画）

/// 広がる衝撃波を、外縁ほど薄く・細くなるリングとして描く。
private func drawShockwave(ctx: GraphicsContext, model: MazeGameModel, s: CGFloat) {
    guard model.shockwave.active else { return }
    let sw     = model.shockwave
    let r      = sw.r * s                                  // 現在の衝撃波半径（ビューpx）
    let cx     = sw.cx * s, cy = sw.cy * s                 // 発射中心（ビューpx）
    let swMaxR = model.swRangeByHp(model.cheeseHp) * s     // 最大半径（HP依存）

    // 拡張進捗 0.0（発射直後）→ 1.0（最大）
    let progress = r / swMaxR
    // 外縁に近いほど透明になるアルファ値
    // ← 0.6 を変えると最大不透明度が変わる
    let alpha = (1 - progress) * 0.6

    // ── 衝撃波リング ──────────────────────────────────────────
    let ring = Path(ellipseIn: CGRect(x: cx - r, y: cy - r, width: r * 2, height: r * 2))
    var sw_ctx = ctx
    sw_ctx.opacity = Double(alpha)
    sw_ctx.stroke(ring,
                  with: .color(Color(red: 1.0, green: 0.922, blue: 0.231)),  // ← 衝撃波の色（黄色）
                  lineWidth: (1 - progress) * 10 + 1)                        // ← 最大線幅（10 + 1）
}

// MARK: drawParticles（ネズミ撃破パーティクルの描画）

/// 飛散パーティクルを、残り寿命に応じて小さく・薄くしながら丸で描く。
private func drawParticles(ctx: GraphicsContext, model: MazeGameModel, s: CGFloat) {
    for p in model.particles {
        // 残りライフ比率（1.0=生成直後 / 0.0=消滅）
        let a = CGFloat(p.life) / CGFloat(p.maxLife)
        // ← 4 を変えるとパーティクルの最大サイズが変わる（s は scale）
        let r = 4 * a * s
        let circle = Path(ellipseIn: CGRect(x: p.x * s - r, y: p.y * s - r,
                                             width: r * 2, height: r * 2))
        var pc = ctx
        pc.opacity = Double(a)
        // ← パーティクルの色を変えたいときはここを変更する
        pc.fill(circle, with: .color(Color(red: 1.0, green: 0.784, blue: 0.196)))  // オレンジ
    }
}

// MARK: drawHUD（スコア・HP・衝撃波バーの描画）
//
// レイアウト概略（論理座標 / s=1, BASE=570, T=30 時）
//   左上:  HP三角(〜116px) → スコア(116px〜)      ※右端余裕 > 200px
//   右上:  ブラストバー幅120px、右端14px内側         ※左端 > 420px → 被らない
//   右下:  ハイスコア、anchor:.trailing で右端固定
//   ※ 左右エリアの境界は画面中央（285px）付近に自然に空白ができる

/// HUD（残りHPの三角アイコン・スコア・衝撃波チャージバー・ハイスコア）を描く。
private func drawHUD(ctx: GraphicsContext, model: MazeGameModel, s: CGFloat, size: CGSize) {
    let T  = model.T * s
    let hp = model.cheeseHp

    // ══════════════════════════════════════
    // 左上: HP アイコン（三角形）
    // ══════════════════════════════════════
    let iconSize: CGFloat = 16 * s   // ← アイコンサイズ（旧12s → +33%）
    let iconY:    CGFloat = 30 * s   // ← 上端からの距離
    let iconStep  = iconSize * 2 + 6 * s  // アイコン間隔

    for i in 0..<3 {
        let cx = 18 * s + CGFloat(i) * iconStep
        var tri = Path()
        tri.move(to:    CGPoint(x: cx,            y: iconY - iconSize))
        tri.addLine(to: CGPoint(x: cx + iconSize, y: iconY + iconSize * 0.65))
        tri.addLine(to: CGPoint(x: cx - iconSize, y: iconY + iconSize * 0.65))
        tri.closeSubpath()
        let fillColor: Color = i < hp
            ? Color(red: 0.95, green: 0.95, blue: 0.95)  // ← HP残: 白
            : Color(white: 0.27)                           // ← HP消費: グレー
        ctx.fill(tri, with: .color(fillColor))
        ctx.stroke(tri, with: .color(Color(white: 0.52)), lineWidth: 1.4)
    }

    // ══════════════════════════════════════
    // 左上: スコア（HP アイコン右隣）
    // ══════════════════════════════════════
    // HP右端 = 18s + 2*iconStep + iconSize
    let hpRightEdge = 18 * s + 2 * iconStep + iconSize
    let scoreText = Text("🧀×\(model.score)")
        .font(.system(size: T * 0.80, weight: .bold))               // ← スコアフォントサイズ（旧0.62）
        .foregroundStyle(Color(red: 1.0, green: 0.839, blue: 0.0))
    ctx.draw(scoreText,
             at: CGPoint(x: hpRightEdge + 10 * s, y: iconY),
             anchor: .leading)   // 右方向にのみ伸びるので画面左に被らない

    // ══════════════════════════════════════
    // 右上: ブラストチャージバー
    // ══════════════════════════════════════
    let ready = model.shockwave.cool == 0
    // チャージ進捗 0.0〜1.0（クールダウン残りから逆算）
    let fill  = ready
        ? CGFloat(1)
        : CGFloat(1) - CGFloat(model.shockwave.cool) / CGFloat(model.SW_COOL)

    let barW:   CGFloat = 120 * s   // ← バー幅（旧90s → +33%）
    let barH:   CGFloat = 14  * s   // ← バー高さ（旧9s → +56%）
    let barPad: CGFloat = 14  * s   // 右端余白
    let bx = size.width - barW - barPad
    let by: CGFloat = 14 * s        // 上端余白

    // バー背景
    ctx.fill(Path(roundedRect: CGRect(x: bx, y: by, width: barW, height: barH),
                  cornerRadius: 5),
             with: .color(Color(white: 0.15)))

    // バー充填
    if fill > 0 {
        let fillColor: Color = ready
            ? Color(red: 1.0, green: 0.922, blue: 0.271)  // ← 満タン: 黄色
            : Color(red: 1.0, green: 0.655, blue: 0.149)  // ← チャージ中: オレンジ
        ctx.fill(Path(roundedRect: CGRect(x: bx, y: by, width: barW * fill, height: barH),
                      cornerRadius: 5),
                 with: .color(fillColor))
    }

    // バーラベル（バー右端揃え・バーの下）
    // ← HP が低いほど 💥 が増える（HP3=💥, HP2=💥💥, HP1=💥💥💥）
    let swMaxR  = model.swRangeByHp(model.cheeseHp)
    let swLabel = swMaxR == model.T * 8 ? "💥💥💥" : swMaxR == model.T * 6.5 ? "💥💥" : "💥"
    let barLabel = Text(ready ? "BLAST \(swLabel)" : "Charging…")
        .font(.system(size: 11 * s, weight: .bold))                   // ← ラベルフォントサイズ（旧9s）
        .foregroundStyle(ready ? Color.white : Color(white: 0.67))
    ctx.draw(barLabel,
             at: CGPoint(x: bx + barW, y: by + barH + 13 * s),
             anchor: .trailing)  // 右端固定 → 画面外にはみ出さない

    // ══════════════════════════════════════
    // 右下: ハイスコア
    // ══════════════════════════════════════
    let hiText = Text("HI 🧀×\(model.highScore)")
        .font(.system(size: T * 0.65, weight: .bold))                 // ← フォントサイズ（旧0.52）
        .foregroundStyle(Color(red: 1.0, green: 0.839, blue: 0.0))
    ctx.draw(hiText,
             at: CGPoint(x: size.width - 14 * s, y: size.height - 16 * s),
             anchor: .trailing)  // 右端固定 → 桁数が増えても左方向にのみ伸びる
}

// MARK: drawDelivered（ゴール到達演出）

/// ステージクリア時の緑オーバーレイと「All Collected! / Next Stage…」メッセージを描く。
private func drawDelivered(ctx: GraphicsContext, model: MazeGameModel, s: CGFloat, size: CGSize) {
    let timer = model.deliveredTimer  // 残りフレーム数（110→0）

    // ← 20 フレームかけてフェードイン、0.65 が最大不透明度
    let alpha = timer > 20 ? 0.65 : (CGFloat(timer) / 20) * 0.65

    // 緑のオーバーレイ
    var ov = ctx
    ov.opacity = Double(alpha)
    ov.fill(Path(CGRect(origin: .zero, size: size)),
            with: .color(Color(red: 0, green: 0.235, blue: 0)))  // ← オーバーレイ色

    // ── メインメッセージ ──────────────────────────────────────
    let t1 = Text("🧀 All Collected!")
        .font(.system(size: model.T * 1.6 * s, weight: .bold, design: .rounded))
        .foregroundStyle(Color(red: 1.0, green: 0.922, blue: 0.271))
    ctx.draw(t1, at: CGPoint(x: size.width / 2, y: size.height * 0.38))

    // ── サブメッセージ ────────────────────────────────────────
    let t2 = Text("Next Stage...")
        .font(.system(size: model.T * 0.8 * s, weight: .bold, design: .rounded))
        .foregroundStyle(Color(red: 0.647, green: 0.839, blue: 0.654))
    ctx.draw(t2, at: CGPoint(x: size.width / 2, y: size.height * 0.52))
}

// MARK: - MazeResultView（リザルト画面）

/// ゲームオーバー画面。スコア・ハイスコア・新記録バナー・もう一度／タイトルへ戻るボタン。
private struct MazeResultView: View {
    var model: MazeGameModel

    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            // ゲームオーバー絵文字
            Text("😢").font(.system(size: 56))  // ← サイズ変更可

            // ── 新記録バナー（新記録のときのみ表示）──────────
            if model.isNewRecord {
                Text("🎉 New Record!")
                    .font(.system(size: 22, weight: .black, design: .rounded))
                    .foregroundStyle(DS.gold)
                    .padding(.horizontal, 24).padding(.vertical, 10)
                    .background(DS.gold.opacity(0.12),
                                in: RoundedRectangle(cornerRadius: DS.sectionRadius))
            }

            // ── スコア表示 ────────────────────────────────────
            VStack(spacing: 4) {
                Text("Cheese Collected")
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .foregroundStyle(DS.muted)
                Text("🧀×\(model.score)")
                    .font(.system(size: 52, weight: .black, design: .rounded))  // ← スコア数値サイズ
                    .foregroundStyle(DS.gold)
            }
            .padding(.vertical, 20).frame(maxWidth: .infinity)
            .background(DS.card, in: RoundedRectangle(cornerRadius: DS.sectionRadius))
            .padding(.horizontal, 24)

            // ── ハイスコア表示 ────────────────────────────────
            HStack(spacing: 8) {
                Text("🏆").font(.system(size: 20))
                Text("Best Record")
                    .font(.system(size: 16, weight: .medium, design: .rounded))
                    .foregroundStyle(DS.muted)
                Text("🧀×\(model.highScore)")
                    .font(.system(size: 22, weight: .black, design: .rounded))
                    .foregroundStyle(DS.gold)
            }
            .padding(.horizontal, 20).padding(.vertical, 10)
            .background(DS.card, in: RoundedRectangle(cornerRadius: DS.sectionRadius))

            Spacer()

            // ── ボタン群 ──────────────────────────────────────
            VStack(spacing: 12) {

                // もういちどあそぶ
                Button {
                    SoundManager.shared.vibrate()
                    SoundManager.shared.playTap()
                    model.startGame()
                } label: {
                    Text("Play Again")
                        .font(.system(size: 22, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity).padding(.vertical, 18)
                        .background(
                            RoundedRectangle(cornerRadius: DS.btnRadius)
                                .fill(DS.primary)
                                .shadow(color: DS.primary.opacity(0.35), radius: 8, x: 0, y: 4)
                        )
                }
                .buttonStyle(.plain)

                // タイトルへもどる（MazeGameModel.gameState を .title に戻す）
                Button {
                    SoundManager.shared.vibrate()
                    withAnimation(.easeInOut(duration: 0.3)) { model.returnToTitle() }
                } label: {
                    Text("Back to Title")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundStyle(DS.muted)
                        .frame(maxWidth: .infinity).padding(.vertical, 14)
                        .background(DS.card, in: RoundedRectangle(cornerRadius: DS.btnRadius))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 24).padding(.bottom, 24)
        }
    }
}
