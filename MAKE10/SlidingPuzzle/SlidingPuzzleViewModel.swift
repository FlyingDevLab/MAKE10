//
//  SlidingPuzzleViewModel.swift
//  FDL-TenBlitz
//
//  Created by 空飛ぶ研究室(FlyingDevLab) on 2026/11/03.
//

// スライドパズル（クロツキ・箱入り娘・華容道）の盤を動かす仕組み。3つのゲームで共有している。
// ここを直すと3つすべてが変わるので、直したら3つとも開いて確かめること。
// （Web 版 /kids/shared/klotski.js を移したもの。考え方の説明はあちらと揃えている）
//
// ★ 盤面の持ち方 ★
//   マスの二次元配列は持たない。駒を { x, y, w, h } の長方形としてだけ持ち、
//   重なりは長方形どうしの交差（isFree）1本で判定する。駒は10個しかないので、毎回すべてと比べても軽い。
//   配列で持つと、2×2 や 1×2 の駒を置くたびに複数のマスへ書き込むことになり、
//   書き込み漏れが「駒が重なって見える」という形で静かに現れる。長方形なら駒の位置は常に1か所。
//
// ★ 手数の数え方 ★
//   同じ駒を続けて動かしている間は1手として数える。このパズルの慣習で、
//   「橫刀立馬の最短81手」もこの数え方による。1マスごとに数えると手数が倍以上になり、目標が意味を持たなくなる。
//
// ★ 時間は計らない ★
//   動いている時計は、こどもにとって「急がなければいけない」という合図になる。
//   じっと盤を眺めて考えている時間こそが中身なので、記録も手数だけにしている。
//
// ★ 盤面は保存しない ★
//   途中でやめたら最初の配置からになる。盤面を復元すると「解けない形で固まったまま再開する」ことがあり、
//   やり直しのボタンを押すまで抜けられなくなるため。
//
// ★ エネルギーは、解けたときだけ ★
//   動かすたびに増やすと、同じ駒を行ったり来たりさせるだけで増やせてしまう。
//   解けたときに「最短の手数 × 倍率」を渡し、最短で解けたらさらに上乗せする（EnergyRewards の表を参照）。

import SwiftUI

@Observable
final class SlidingPuzzleViewModel {

    static let cols = 4
    static let rows = 5

    private enum C {
        /// 出口から抜けていく時間（秒）← 変更可
        static let escapeDuration: Double = 0.9
        /// 抜けきってから結果を出すまでの時間（秒）← 変更可
        static let resultDelay:    Double = 1.1
    }

    let kind: SlidingPuzzleKind

    // MARK: 盤の状態

    private(set) var pieces: [SlidingPiece] = []
    /// 手数（同じ駒を続けて動かす間は1手）
    private(set) var moves:  Int = 0
    /// 解けたか（このあとは盤に触れない）
    private(set) var isWon:  Bool = false
    /// 出口へ運ぶ駒が抜けていく途中か（盤の下へ滑らせて消す演出）
    private(set) var isEscaping: Bool = false
    /// 結果のカードを出すか（抜けきってから出す）
    private(set) var showsResult: Bool = false

    /// 最後に動かした駒。別の駒に触ったときだけ新しい1手として数える
    private var lastID: String? = nil

    private struct Snapshot {
        let positions: [(Int, Int)]
        let moves:     Int
        let lastID:    String?
    }
    private var history: [Snapshot] = []

    var canUndo: Bool { !history.isEmpty && !isWon && drag == nil }

    // MARK: 結果

    /// 今回で最少手数を更新したか
    private(set) var isNewBest:    Bool = false
    /// 更新する前の記録（初めて解いたときは nil）
    private(set) var previousBest: Int? = nil

    /// 自己最少手数（未クリアなら nil）
    var best: Int? { ScoreBoard.fewestMoves(for: kind.bestKey) }
    /// クリアした回数（見せるだけ）
    var clears: Int { ScoreBoard.highScore(for: kind.clearsKey) }

    /// 予約した「結果を出す」が、やり直したあとの盤で動かないようにする番号（TenPuzzleViewModel と同じ考え方）
    private var generation = 0

    init(kind: SlidingPuzzleKind) {
        self.kind = kind
        reset()
    }

    // MARK: - 盤の読み取り

    /// 駒 p を (x, y) に置けるか。盤の外に出る場合と、他の駒と1マスでも重なる場合に false。
    private func isFree(_ index: Int, x: Int, y: Int) -> Bool {
        let p = pieces[index]
        if x < 0 || y < 0 || x + p.w > Self.cols || y + p.h > Self.rows { return false }
        for (j, q) in pieces.enumerated() where j != index {
            // 長方形の交差判定。4辺すべてで重なっていれば重なっている
            if x < q.x + q.w && x + p.w > q.x && y < q.y + q.h && y + p.h > q.y { return false }
        }
        return true
    }

    private enum Axis { case x, y }

    /// (bx, by) から軸方向へ何マス進めるか。1マスずつ isFree で試すので、途中に駒があればそこで止まる。
    /// 指をどれだけ引いても、通れない駒をすり抜けないのはこの範囲のため。
    private func freeRange(_ index: Int, bx: Int, by: Int, axis: Axis) -> (pos: Int, neg: Int) {
        let ax = axis == .x ? 1 : 0, ay = 1 - ax
        var pos = 0, neg = 0
        while isFree(index, x: bx + ax * (pos + 1), y: by + ay * (pos + 1)) { pos += 1 }
        while isFree(index, x: bx - ax * (neg + 1), y: by - ay * (neg + 1)) { neg += 1 }
        return (pos, neg)
    }

    private func snapshot() -> Snapshot {
        Snapshot(positions: pieces.map { ($0.x, $0.y) }, moves: moves, lastID: lastID)
    }

    // MARK: - ドラッグ
    //
    // 指で駒をなぞって動かす。要点は3つ。
    //   ・動かせる範囲（freeRange）の外へは出さない。壁や駒をすり抜けない
    //   ・縦か横かは、最初に少し動いた方向で決める
    //   ・マスに揃ったところで直角に引けば、指を離さずに曲がれる

    private struct Drag {
        let index:  Int
        var shiftX: Double = 0       // 曲がったときに「つかんだ位置」をずらした量（マス）
        var shiftY: Double = 0
        var bx:     Int              // 今の軸の始点（曲がると更新される）
        var by:     Int
        let ox:     Int              // 最初の位置（動いたかの判定用）
        let oy:     Int
        var axis:   Axis? = nil
        var range:  (pos: Int, neg: Int) = (0, 0)
        var off:    Double = 0       // 軸に沿って動いている量（マス。範囲で切り落とし済み）
        let before: Snapshot
    }
    private var drag: Drag? = nil

    /// ドラッグ中の駒の id（画面はこの駒だけアニメーションを止め、指に追従させる）
    var draggingID: String? { drag.map { pieces[$0.index].id } }

    /// ドラッグ中の駒の、マス単位の表示位置（半端な位置もとる）。ドラッグしていない駒は nil
    func dragPosition(of piece: SlidingPiece) -> (x: Double, y: Double)? {
        guard let d = drag, pieces[d.index].id == piece.id else { return nil }
        switch d.axis {
        case .x:   return (Double(d.bx) + d.off, Double(d.by))
        case .y:   return (Double(d.bx), Double(d.by) + d.off)
        case nil:  return (Double(d.bx), Double(d.by))
        }
    }

    /// 指が動いた。dx, dy は指を置いた位置からの移動量（マス単位）。
    func dragChanged(_ piece: SlidingPiece, dx rawDX: Double, dy rawDY: Double) {
        guard !isWon else { return }
        if drag == nil {
            guard let index = pieces.firstIndex(where: { $0.id == piece.id }) else { return }
            let p = pieces[index]
            drag = Drag(index: index, bx: p.x, by: p.y, ox: p.x, oy: p.y, before: snapshot())
        }
        guard var d = drag, pieces[d.index].id == piece.id else { return }

        var dx = rawDX - d.shiftX, dy = rawDY - d.shiftY

        if let axis = d.axis {
            // 曲がり角。マスの位置にほぼ揃っていて、直角方向へ充分に引いていて、
            // その引きが進行方向の残りより大きいときだけ曲がる。
            // 条件を緩めると、まっすぐ動かしているだけで勝手に曲がる。
            let k = d.off.rounded()
            let along = axis == .x ? dx : dy
            let perp  = axis == .x ? dy : dx
            if abs(d.off - k) < 0.25 && abs(perp) > 0.35 && abs(perp) > abs(along - k) {
                let nbx = d.bx + (axis == .x ? Int(k) : 0)
                let nby = d.by + (axis == .y ? Int(k) : 0)
                let other: Axis = axis == .x ? .y : .x
                let r2 = freeRange(d.index, bx: nbx, by: nby, axis: other)
                if (perp > 0 ? r2.pos : r2.neg) > 0 {
                    // 曲がった地点を新しい始点にする。つかんだ位置も同じだけずらすと、
                    // 指と駒の相対位置が保たれ、駒が指の下から飛ばない。
                    if axis == .x { d.shiftX += k } else { d.shiftY += k }
                    d.bx = nbx; d.by = nby; d.axis = other; d.range = r2
                    dx = rawDX - d.shiftX; dy = rawDY - d.shiftY
                }
            }
        } else {
            // 0.08マス動くまでは軸を決めない。触れた瞬間の震えで、動かしたくない方向に決まるのを防ぐ。
            guard max(abs(dx), abs(dy)) >= 0.08 else { drag = d; return }
            var axis: Axis = abs(dx) >= abs(dy) ? .x : .y
            var range = freeRange(d.index, bx: d.bx, by: d.by, axis: axis)
            // 選んだ方向には動けず、もう一方なら動ける場合は軸を入れ替える。
            // 斜めに引いたときに「動くはずの駒が動かない」と感じさせないため。
            let along = axis == .x ? dx : dy
            if (along > 0 ? range.pos : range.neg) == 0 {
                let other: Axis = axis == .x ? .y : .x
                let r2 = freeRange(d.index, bx: d.bx, by: d.by, axis: other)
                let perp = other == .x ? dx : dy
                if (perp > 0 ? r2.pos : r2.neg) > 0 { axis = other; range = r2 }
            }
            d.axis = axis
            d.range = range
        }

        // 動かせる範囲で切り落とす。範囲の端より先は指に追従しない
        let raw = d.axis == .x ? dx : dy
        d.off = max(-Double(d.range.neg), min(Double(d.range.pos), raw))
        drag = d
    }

    /// 指が離れた。一番近いマスへ吸着させる（途中で止めても半端な位置には残らない）。
    func dragEnded(_ piece: SlidingPiece) {
        guard let d = drag, pieces[d.index].id == piece.id else { return }
        let k = d.axis == nil ? 0 : Int(d.off.rounded())
        pieces[d.index].x = d.bx + (d.axis == .x ? k : 0)
        pieces[d.index].y = d.by + (d.axis == .y ? k : 0)
        drag = nil

        // 触っただけ・元の位置に戻った場合は手数に数えない
        let p = pieces[d.index]
        if p.x != d.ox || p.y != d.oy {
            SoundManager.shared.playTap()
            commit(p, before: d.before)
        }
    }

    /// 1マスだけ動かす（VoiceOver の操作から使う。Web 版の矢印キーと同じ）。
    func step(_ piece: SlidingPiece, dx: Int, dy: Int) {
        guard !isWon, drag == nil, let index = pieces.firstIndex(where: { $0.id == piece.id }) else { return }
        let p = pieces[index]
        guard isFree(index, x: p.x + dx, y: p.y + dy) else { return }
        let before = snapshot()
        withAnimation(.easeOut(duration: 0.16)) {
            pieces[index].x += dx
            pieces[index].y += dy
        }
        SoundManager.shared.playTap()
        commit(pieces[index], before: before)
    }

    // MARK: - 手の確定

    private func commit(_ p: SlidingPiece, before: Snapshot) {
        // 別の駒に触ったときだけ新しい1手として数える。同じ駒を続けて動かしている間は、何マス動かしても1手。
        if p.id != lastID {
            history.append(before)
            moves  += 1
            lastID  = p.id
        }
        checkWin()
    }

    private func checkWin() {
        guard let m = pieces.first(where: { $0.id == kind.goalID }),
              m.x == kind.goal.x, m.y == kind.goal.y else { return }

        isWon        = true
        previousBest = best
        isNewBest    = ScoreBoard.saveIfFewer(moves: moves, for: kind.bestKey)
        ScoreBoard.saveIfBetter(score: clears + 1, for: kind.clearsKey)

        // クリアボーナス = 最短の手数 × 倍率。最短で解けたら perfectBonus を上乗せする
        var bonus = Double(kind.par) * EnergyRewards.slidingPuzzleBonusRate
        if moves == kind.par { bonus += EnergyRewards.perfectBonus }
        EnergyStore.shared.grantClearBonus(bonus)
        GameDailyBonus.shared.claim(kind.pickerSelection)   // その日はじめてなら「きょう はじめての ボーナス」
        SoundManager.shared.playCorrect()

        // 動きを減らす設定のときは駒を飛び出させず、その場に置いたまま結果を出す
        if UIAccessibility.isReduceMotionEnabled {
            showsResult = true
            return
        }
        withAnimation(.easeIn(duration: C.escapeDuration)) { isEscaping = true }
        let gen = generation
        DispatchQueue.main.asyncAfter(deadline: .now() + C.resultDelay) { [weak self] in
            guard let self, self.generation == gen else { return }
            withAnimation(.easeOut(duration: 0.3)) { self.showsResult = true }
        }
    }

    // MARK: - 戻す・やり直す

    func undo() {
        guard canUndo, let s = history.popLast() else { return }
        withAnimation(.easeOut(duration: 0.16)) {
            for i in pieces.indices {
                pieces[i].x = s.positions[i].0
                pieces[i].y = s.positions[i].1
            }
        }
        moves  = s.moves
        lastID = s.lastID
        SoundManager.shared.playTap()
    }

    /// 最初の配置に戻す。配置表は毎回作り直して使う（前の遊びの位置を引き継がないように）。
    func reset() {
        generation  += 1
        drag         = nil
        pieces       = kind.pieces
        moves        = 0
        lastID       = nil
        history      = []
        isWon        = false
        isEscaping   = false
        showsResult  = false
        isNewBest    = false
        previousBest = nil
        EnergyStore.shared.beginSession()   // 結果画面に出す「今回の獲得量」を 0 に戻す
    }
}
