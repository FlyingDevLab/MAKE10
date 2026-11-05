//
//  RiverCrossingViewModel.swift
//  FDL-TenBlitz
//
//  Created by 空飛ぶ研究室(FlyingDevLab) on 2026/11/03.
//

// 川わたりパズルの進行を受け持つ ViewModel。
//
// ★ このファイルの責務 ★
//   - ステージの選択（最後に選んだステージを覚えておく）
//   - 駒を舟に乗せる・降ろす、舟を渡す、ひとつ前に戻す、やり直す
//   - ルール違反のときに「何が起きかけたか」を見せてから自動で引き返す
//   - クリアの判定と、ステージごとの最少回数の記録、エネルギーの受け渡し
//
// ★ 回数は「川を渡った回数」 ★
//   舟に乗せる・降ろすは数えない。わたる を押して渡り切った回数だけ。
//   ルール違反で引き返した回は数えない。失敗は回数を汚さない。
//
// ★ ルール違反の見せ方 ★
//   違反になる組み合わせでも、舟は渡り切る。渡った先で何が起きかけたかを
//   出してから、約1.2秒後に自動で引き返す。
//   「押す前に止める」方式にしなかったのは、何が駄目なのかを
//   見せた方がこどもには伝わるため。戻すのは自動なので手が止まらない。
//   なお、誰も食べられないし、誰も泣かない。起きかけたところで引き返す。
//
// ★ 時間は計らない ★
//   動いている時計は、こどもにとって「急がなければいけない」という合図になる。
//   川わたりは急いで解くものではないし、岸を眺めて誰を乗せるか考えている時間こそが中身。
//   記録に残すのも回数だけにしている。
//
// ★ エネルギーは、わたりきったときだけ ★
//   渡るたびに増やすと、戻す と わたる をくり返すだけで増やせてしまう。
//   クリアしたときに「最短の回数 × 倍率」を渡し、最短で渡れたらさらに上乗せする。
//   （Web 版と同じ盤・同じルール。エネルギーはアプリだけのもの）
//
// ★ ステージは順番に開く ★
//   Web 版は4つとも最初から選べるが、アプリは1問目をクリアすると2問目が開く形にしている。
//   4問目をクリアするとクロツキが開く（PuzzleProgress.swift を参照）。

import SwiftUI

@Observable
final class RiverCrossingViewModel {

    private enum C {
        /// 舟が渡るのにかける時間（秒）← 変更可
        static let crossDuration: Double = 0.55
        /// 違反を見せてから引き返すまでの時間（秒）← 変更可
        static let holdDuration:  Double = 1.2
        /// 全員が着いてから結果を出すまでの時間（秒）← 変更可
        static let resultDelay:   Double = 0.4
    }

    // MARK: ステージ

    private(set) var stage: RiverStage

    // MARK: 盤の状態

    /// 駒の id → 居場所
    private(set) var whereIs: [String: RiverSide] = [:]
    /// 舟が どちらの岸に 着けてあるか（.near か .far）
    private(set) var boatAt: RiverSide = .near
    /// 渡った回数
    private(set) var moves: Int = 0
    /// 画面の下に出す一言。nil なら何も出さない
    private(set) var message: RiverMessage? = nil
    /// 舟が動いている間・違反を見せている間。この間は操作を受け付けない
    private(set) var isBusy: Bool = false
    /// 全員わたりきったか
    private(set) var isCleared: Bool = false

    /// 渡る直前の状態。戻す と、違反で引き返すときに使う
    private struct Snapshot {
        let whereIs: [String: RiverSide]
        let boatAt:  RiverSide
    }
    private var history: [Snapshot] = []

    var canUndo:  Bool { !isCleared && !history.isEmpty }
    var canCross: Bool { !isCleared && !crew.isEmpty }

    // MARK: クリアの結果

    /// 今回で最少回数を更新したか
    private(set) var isNewBest: Bool = false
    /// 更新する前のベスト（初めてクリアしたときは nil）
    private(set) var previousBest: Int? = nil
    /// 今回のクリアであたらしく開いた段（「○○が ひらいた！」に使う）
    private(set) var openedStep: PuzzleStep? = nil

    // ★ 盤の世代番号が要る理由 ★
    //   渡る処理は「舟が着いたあと」「違反を見せたあと」を asyncAfter で予約する。
    //   その待ち時間のうちにステージを切り替えたりやり直したりすると、予約していた
    //   後始末が新しい盤の上で動いてしまう。予約した時点の番号を覚えておき、
    //   発火したときに変わっていたら何もせず捨てる（TenPuzzleViewModel と同じ考え方）。
    private var generation: Int = 0

    // MARK: - 初期化

    init() {
        let saved = UserDefaults.standard.string(forKey: UDKey.riverCrossingLastStage)
        // 前に選んでいたステージから始める。開いていないものが保存されていたら1問目に戻す
        stage = saved.flatMap(RiverStage.init(rawValue:))
            .flatMap { PuzzleProgress.shared.isUnlocked($0.step) ? $0 : nil } ?? .wolf
        setUpBoard()
    }

    // MARK: - 盤の読み取り

    /// その居場所にいる駒（ステージの表の順）
    func actors(at side: RiverSide) -> [RiverActor] {
        stage.actors.filter { whereIs[$0.id] == side }
    }

    /// その駒がいまどこにいるか
    func side(of actor: RiverActor) -> RiverSide {
        whereIs[actor.id] ?? .near
    }

    private func ids(at side: RiverSide) -> Set<String> {
        Set(stage.actors.map(\.id).filter { whereIs[$0] == side })
    }

    private var crew: Set<String> { ids(at: .boat) }

    /// 舟の空いている席の数
    var emptySeats: Int { max(0, stage.seats - crew.count) }

    /// その駒に触れるか。舟が着いていない岸の駒は触れない（触れても何も起きない方が迷う）。
    func canTap(_ actor: RiverActor) -> Bool {
        guard !isCleared else { return false }
        let side = whereIs[actor.id]
        return side == .boat || side == boatAt
    }

    /// 最少回数の記録（未クリアなら nil）
    func best(for stage: RiverStage) -> Int? {
        ScoreBoard.fewestMoves(for: stage.bestKey)
    }

    // MARK: - ステージ

    /// そのステージが開いているか
    func isUnlocked(_ stage: RiverStage) -> Bool {
        PuzzleProgress.shared.isUnlocked(stage.step)
    }

    func select(_ newStage: RiverStage) {
        guard newStage != stage, isUnlocked(newStage) else { return }
        stage = newStage
        UserDefaults.standard.set(newStage.rawValue, forKey: UDKey.riverCrossingLastStage)
        restart()
    }

    /// 次のステージ（最後のステージなら nil）
    var nextStage: RiverStage? {
        let all = RiverStage.allCases
        guard let i = all.firstIndex(of: stage), i + 1 < all.count else { return nil }
        return all[i + 1]
    }

    /// 盤を最初の状態に戻して、新しく遊び始める。
    func restart() {
        setUpBoard()
        EnergyStore.shared.beginSession()   // 結果画面に出す「今回の獲得量」を 0 に戻す
    }

    /// 盤を最初の状態にする。途中の盤は保存しない（途中でやめたら最初から）。
    /// init でも呼ぶので、ここでは EnergyStore に触らない
    /// （理由は SlidingPuzzleViewModel の「init で EnergyStore.beginSession() を呼ばない理由」を参照）。
    private func setUpBoard() {
        generation  += 1
        whereIs      = Dictionary(uniqueKeysWithValues: stage.actors.map { ($0.id, RiverSide.near) })
        boatAt       = .near
        moves        = 0
        history      = []
        message      = nil
        isBusy       = false
        isCleared    = false
        isNewBest    = false
        previousBest = nil
        openedStep   = nil
    }

    // MARK: - 操作

    /// 駒をタップする。岸にいれば舟へ、舟にいれば今いる側の岸へ。
    func tap(_ actor: RiverActor) {
        guard !isBusy, !isCleared else { return }

        if whereIs[actor.id] == .boat {
            whereIs[actor.id] = boatAt
            message = nil
            SoundManager.shared.playTap()
            return
        }
        guard whereIs[actor.id] == boatAt else { return }

        var next = crew
        next.insert(actor.id)
        if next.count > stage.seats {
            say(.boatFull)
            return
        }
        if let problem = stage.boardingProblem(crew: next) {
            say(problem)
            return
        }

        whereIs[actor.id] = .boat
        message = nil
        SoundManager.shared.playTap()
    }

    /// 渡る。渡り切ってから、両岸に残った顔ぶれを見る。
    func cross() {
        guard !isBusy, !isCleared else { return }
        let crew = self.crew
        guard !crew.isEmpty else { return }

        // 漕げる人がいないときは、ここで初めて理由を伝える。
        // ボタンを押せなくしてしまうと、なぜ進めないのかが分からない（8にんの いかだで「こげるのは3人だけ」を押して覚えてもらう）。
        if let rowers = stage.rowers, rowers.isDisjoint(with: crew) {
            say(.noRower)
            return
        }

        let before = Snapshot(whereIs: whereIs, boatAt: boatAt)
        let gen = generation
        isBusy  = true
        message = nil
        SoundManager.shared.playTap()

        // 舟の居場所だけ先に変える。乗っている駒は舟に乗ったまま一緒に動く
        withAnimation(.easeInOut(duration: crossDuration)) {
            boatAt = boatAt.opposite
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + crossDuration) { [weak self] in
            guard let self, self.generation == gen else { return }   // 盤が入れ替わっていた
            withAnimation(.easeOut(duration: 0.2)) {
                for id in crew { self.whereIs[id] = self.boatAt }    // 着いた岸で降りる
            }

            if let problem = self.stage.bankProblem(self.ids(at: .near))
                          ?? self.stage.bankProblem(self.ids(at: .far)) {
                // 起きかけたところを見せてから、乗り直して引き返す。
                // before は「乗ったまま、前の岸にいる」状態なので、戻すとそのまま舟に乗り直して帰る絵になる。
                self.say(problem)
                DispatchQueue.main.asyncAfter(deadline: .now() + self.holdDuration) { [weak self] in
                    guard let self, self.generation == gen else { return }
                    withAnimation(.easeInOut(duration: self.crossDuration)) {
                        self.restore(before)
                    }
                    self.isBusy = false
                }
                return
            }

            self.moves  += 1
            self.history.append(before)
            self.isBusy  = false
            if self.ids(at: .far).count == self.stage.actors.count {
                self.win()
            }
        }
    }

    func undo() {
        guard !isBusy, canUndo, let last = history.popLast() else { return }
        withAnimation(.easeInOut(duration: 0.3)) { restore(last) }
        moves   = max(0, moves - 1)
        message = nil
        SoundManager.shared.playTap()
    }

    private func restore(_ snapshot: Snapshot) {
        whereIs = snapshot.whereIs
        boatAt  = snapshot.boatAt
    }

    private func say(_ problem: RiverMessage) {
        message = problem
        SoundManager.shared.playWrong()
    }

    // MARK: - クリア

    private func win() {
        previousBest = best(for: stage)
        isNewBest    = ScoreBoard.saveIfFewer(moves: moves, for: stage.bestKey)

        // クリアボーナス = 最短の回数 × 倍率。むずかしいステージほど最短が長いので、そのまま重みになる。
        // 最短で渡れたら perfectBonus を上乗せする（EnergyRewards の表を参照）
        var bonus = Double(stage.par) * EnergyRewards.riverCrossingBonusRate
        if moves == stage.par { bonus += EnergyRewards.perfectBonus }
        EnergyStore.shared.grantClearBonus(bonus)
        // 次のステージ（4問目ならクロツキ）を開き、はじめてのクリアなら初回クリア報酬を渡す
        let result = PuzzleProgress.shared.clear(stage.step)
        EnergyStore.shared.grantFirstClearBonus(result.firstClearReward)
        openedStep = result.opened.first
        GameDailyBonus.shared.claim(.riverCrossing)   // その日はじめてなら「きょう はじめての ボーナス」（GameDailyBonus.swift を参照）

        SoundManager.shared.playCorrect()

        // ★ 結果を少し待ってから出す理由 ★
        //   全員がむこう岸に着いた様子を見せるため。また、渡り終えた処理と同じ瞬間に isCleared を変えると、
        //   新記録のときに結果のカードが出ず、ボタンの状態も古いまま残ることがあった
        //   （スライドパズルは結果を遅らせて出していて、この症状が起きない）。
        isBusy = true
        let gen = generation
        DispatchQueue.main.asyncAfter(deadline: .now() + C.resultDelay) { [weak self] in
            guard let self, self.generation == gen else { return }
            self.isBusy = false
            withAnimation(.easeOut(duration: 0.3)) { self.isCleared = true }
        }
    }

    // MARK: - 動きを減らす設定

    // 「視差効果を減らす」を有効にしている人には、舟を滑らせずに瞬間移動させる。
    // 違反を見せる時間は逆に少し長くして、何が起きたかを読む時間を取る。
    private var crossDuration: Double {
        UIAccessibility.isReduceMotionEnabled ? 0 : C.crossDuration
    }
    private var holdDuration: Double {
        UIAccessibility.isReduceMotionEnabled ? C.holdDuration + 0.4 : C.holdDuration
    }
}

// MARK: - 記録のキー

extension RiverStage {
    /// 最少回数を保存するキー
    var bestKey: String {
        switch self {
        case .wolf:   return UDKey.riverCrossingBestWolf
        case .weight: return UDKey.riverCrossingBestWeight
        case .pairs:  return UDKey.riverCrossingBestPairs
        case .raft:   return UDKey.riverCrossingBestRaft
        }
    }

    /// 解放の道のりの中での位置（PuzzleProgress.swift を参照）
    var step: PuzzleStep {
        switch self {
        case .wolf:   return .river1
        case .weight: return .river2
        case .pairs:  return .river3
        case .raft:   return .river4
        }
    }
}
