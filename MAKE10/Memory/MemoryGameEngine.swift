//
//  MemoryGameEngine.swift
//  FDL-TenBlitz
//
//  Created by 空飛ぶ研究室(FlyingDevLab) on 2026/09/06.
//

// どうぶつめくり（神経衰弱）のゲームロジック。
// 盤面の生成・タップの受付・一致判定・クリア判定だけを担当する。
//
// ★ このクラスが知らないこと ★
//   絵文字・画像・色・レイアウトを一切知りません。
//   カードは pairID という文字列でしか区別しておらず、
//   絵柄の中身は CardFaceProvider に委ねています（MemoryModels.swift 参照）。
//   そのため、カード面を別のものに差し替えてもこのファイルは変更不要です。
//
// ★ このゲームの操作方針 ★
//   連打して勢いよく進められることを大事にしています。そのため一般的な神経衰弱と違い、
//   不一致の待ち時間中も入力を止めません（先行入力）。
//   待っている2枚が伏せられる前に別のカードを叩くと、待機を打ち切って次の手番へ進みます。
//
// ★ 先行入力を許すと何が壊れるのか ★
//   壊れる原因はタップそのものではなく、「あとで実行される予約」の方にあります。
//   不一致になると「◯秒後に2枚を伏せる」という処理を予約しますが、
//   その予約が実行される頃には、先行入力によって盤面が次の手番に進んでいる可能性があります。
//   何も対策しないと、めくったばかりのカードや、揃ったばかりのペアを
//   古い予約が伏せてしまい、盤面が静かに壊れます。
//
// ★ 対策：世代番号 ★
//   手番が切り替わるたびに generation を1つ進めます。
//   予約する処理には、そのときの generation を持たせておき、
//   実行の瞬間に現在の値と一致するかを確かめます。
//   一致しなければ「自分は古い予約だ」と判断して何もせずに終わります。
//   これで、予約が後から悪さをする経路をふさげます。
//
// ★ 最短表示時間と先行入力の保留 ★
//   2枚目が表になった直後のタップまで受け付けると、
//   連打している子は何がめくれたのかを一度も見られず、覚えようがなくなります。
//   そこで、めくってから minRevealTime の間は伏せません。
//   その間に来たタップは捨てずに1件だけ覚えておき（bufferedTapID）、
//   時間が来た瞬間に実行します。こうすると「叩いたのに無反応」が起きません。

import SwiftUI
import QuartzCore   // CACurrentMediaTime()（経過時間の計測に使う単調時計）

// MARK: - MemoryGameEngine

// @Observable の解説は AppSettings.swift 冒頭を参照。

/// どうぶつめくりの盤面と進行を管理するクラス。
@Observable
final class MemoryGameEngine {

    // MARK: - 公開状態

    /// 盤面のカード一覧。表示はこの並び順のまま5列で折り返す。
    private(set) var cards: [CardState] = []

    /// 現在の局面。View はこれを見て入力可否や演出を切り替える。
    private(set) var phase: MemoryPhase = .idle

    // MARK: - 非公開

    /// カード面の供給役。ロジックはこれ越しにしか絵柄を知らない。
    private let faceProvider: CardFaceProvider

    // ★ 世代番号 ★
    //   手番が切り替わるたびに1つ進む。予約された処理はこの値を照合して、
    //   古くなっていれば自分から何もせず終わる（ファイル冒頭の解説を参照）。
    private var generation: Int = 0

    /// 2枚目を表向きにした時刻。最短表示時間の判定に使う。
    /// Date() ではなく CACurrentMediaTime() を使うのは、
    /// 端末の時刻変更やスリープ復帰の影響を受けにくいため（SoundManager と同じ考え方）。
    private var judgingStartedAt: TimeInterval = 0

    /// 最短表示時間の内側に来たタップを1件だけ覚えておく場所。
    /// 新しいタップが来たら上書きする（最後に押した1枚だけを活かす）。
    private var bufferedTapID: UUID? = nil

    /// 盤面を生成済みかどうか。onAppear が複数回呼ばれても作り直さないための番人。
    private var hasStarted: Bool = false

    // MARK: - 初期化

    // ★ 引数に既定値を持たせている理由 ★
    //   通常は MemoryGameEngine() と書くだけで動物の絵文字が使われます。
    //   一方で、別の絵柄を使いたい場合や動作確認をしたい場合には、
    //   呼び出し側から別の CardFaceProvider を渡せるようにしてあります。

    /// - Parameter faceProvider: カード面の供給役。既定は動物絵文字。
    init(faceProvider: CardFaceProvider = AnimalFaceProvider()) {
        self.faceProvider = faceProvider
    }

    // MARK: - 盤面の生成

    /// 未生成のときだけ盤面を作る。onAppear から呼ぶ用。
    func startIfNeeded() {
        guard !hasStarted else { return }
        hasStarted = true
        start()
    }

    /// 盤面を作り直す。「もういちど」から呼ぶ用。
    func start() {
        // 進行中の予約をすべて無効化してから作り直す。
        // これを忘れると、前の盤面の予約が新しい盤面のカードを触りにくる。
        generation += 1
        bufferedTapID    = nil
        judgingStartedAt = 0

        // 識別子をペア数ぶん受け取り、1つにつき2枚ずつカードを作る。
        let pairIDs = faceProvider.pairIdentifiers(count: MemoryTuning.pairCount)
        var built: [CardState] = []
        for pairID in pairIDs {
            built.append(CardState(pairID: pairID))
            built.append(CardState(pairID: pairID))
        }

        cards      = built.shuffled()
        phase      = .idle
        hasStarted = true
    }

    // MARK: - カード面の取り出し

    // ★ View が faceProvider を直接持たない理由 ★
    //   カード面への入口をこの2つのメソッドだけに絞ることで、
    //   「絵柄を参照している場所は CardFaceProvider の内側だけ」という状態を保てます。
    //   差し替え点が1か所であることが、この設計の要です。

    /// カードの表面を返す。
    func face(for card: CardState) -> CardFace {
        faceProvider.face(for: card.pairID)
    }

    /// カードの VoiceOver 用ラベルを返す。裏向きのカードは中身を明かさない。
    func accessibilityLabel(for card: CardState) -> LocalizedStringKey {
        guard card.isFaceUp || card.isMatched else { return "memory_card_face_down" }
        return faceProvider.accessibilityLabel(for: card.pairID)
    }

    // MARK: - タップの受付

    /// カードがタップされたときに呼ぶ。局面に応じて処理を振り分ける。
    func tap(_ id: UUID) {
        // ★ 添字ではなく id で引く理由 ★
        //   添字を持ち回ると、配列が変わったときに別のカードを指したり
        //   範囲外アクセスでクラッシュしたりします。
        //   id で引いて guard で受ければ、対象が無くても安全に何もせず終われます。
        guard let index = cards.firstIndex(where: { $0.id == id }) else { return }

        // 確定済み・すでに表向きのカードは受け付けない。
        // 1枚目と同じカードをもう一度叩いた場合もここで無反応になる。
        // （取り消しにしないのは、連打時の指のはねで意図せず戻ってしまうため）
        guard !cards[index].isMatched, !cards[index].isFaceUp else { return }

        switch phase {
        case .idle:
            revealCard(at: index)
            phase = .oneUp(id)

        case .oneUp(let firstID):
            revealCard(at: index)
            phase = .judging(first: firstID, second: id)
            beginJudging(first: firstID, second: id)

        case .judging:
            handleTapDuringJudging(id)

        case .cleared:
            // クリア後は盤面を触らせない。
            return
        }
    }

    // MARK: - 判定

    /// 2枚目がめくられた直後の処理。一致なら音を鳴らし、決着を予約する。
    private func beginJudging(first: UUID, second: UUID) {
        judgingStartedAt = CACurrentMediaTime()

        guard let f = index(of: first), let s = index(of: second) else {
            // 想定外の状態。盤面を壊すより入力待ちへ戻す方が安全。
            phase = .idle
            return
        }

        let isMatch = cards[f].pairID == cards[s].pairID

        // 一致音は「揃った」と分かった瞬間に鳴らす（決着を待たない）。
        // 不一致は無音。神経衰弱では不一致の方が圧倒的に多く、
        // そのたびに音を鳴らすと失敗を責め続けているように聞こえるため。
        if isMatch {
            SoundManager.shared.playCorrect()
        }

        generation += 1
        let gen  = generation
        let wait = isMatch ? MemoryTuning.matchHold : MemoryTuning.mismatchHold

        // ① 通常の決着。待ち時間いっぱいまで待ってから処理する。
        DispatchQueue.main.asyncAfter(deadline: .now() + wait) { [weak self] in
            guard let self, gen == self.generation else { return }   // 古い予約は捨てる
            self.resolveJudging(next: nil)
        }

        // ② 保留されたタップの実行。最短表示時間が過ぎた時点で確認する。
        //    覚えたタップが無ければ何もせず、①の予約をそのまま待つ。
        DispatchQueue.main.asyncAfter(deadline: .now() + MemoryTuning.minRevealTime) { [weak self] in
            guard let self, gen == self.generation else { return }
            guard let pending = self.bufferedTapID else { return }
            self.bufferedTapID = nil
            self.resolveJudging(next: pending)
        }
    }

    /// 判定待ちの最中にカードがタップされたときの処理（先行入力）。
    private func handleTapDuringJudging(_ id: UUID) {
        let elapsed = CACurrentMediaTime() - judgingStartedAt

        if elapsed < MemoryTuning.minRevealTime {
            // まだ2枚目を見せている最中。捨てずに1件だけ覚えておく。
            bufferedTapID = id
        } else {
            // 十分に見せた後なので、待機を打ち切って次の手番へ進む。
            resolveJudging(next: id)
        }
    }

    // ★ 一致と不一致で処理を分けていない理由 ★
    //   「今の2枚に決着をつけて、必要なら次のタップを流す」という手順は
    //   一致でも不一致でも同じ形です。1か所にまとめることで、
    //   先行入力の経路と通常の経路が必ず同じ道を通ることを保証できます。

    /// 判定待ちの2枚に決着をつける。next があれば続けてそのカードをめくる。
    private func resolveJudging(next: UUID?) {
        // 局面が判定待ちでなければ、すでに決着済み。二重処理を防ぐ。
        guard case .judging(let firstID, let secondID) = phase else { return }

        // 決着した時点で手番が変わるため、残っている予約を無効化する。
        generation   += 1
        bufferedTapID = nil

        if let f = index(of: firstID), let s = index(of: secondID) {
            if cards[f].pairID == cards[s].pairID {
                // 一致：表向きのまま残し、確定済みにする。
                // View 側で薄く表示され、残っているカードが目立つようになる。
                cards[f].isMatched = true
                cards[s].isMatched = true
            } else {
                // 不一致：2枚とも裏向きに戻す。伏せる動きは View がアニメーションする。
                cards[f].isFaceUp = false
                cards[s].isFaceUp = false
            }
        }

        // 全ペアが揃ったらクリア。ここが唯一のクリア判定地点なので、
        // 二重にクリア処理が走ることはない。
        if cards.allSatisfy({ $0.isMatched }) {
            phase = .cleared
            SoundManager.shared.playTenClear()
            return
        }

        phase = .idle

        // 先行入力で預かっていたタップを、通常のタップとして流し直す。
        // 局面は .idle に戻っているため、1枚目をめくる処理として正しく扱われる。
        if let next {
            tap(next)
        }
    }

    // MARK: - 補助

    /// カードを表向きにして、めくる音を鳴らす。
    private func revealCard(at index: Int) {
        cards[index].isFaceUp = true
        SoundManager.shared.playTap()
    }

    /// id からカードの添字を引く。見つからなければ nil。
    private func index(of id: UUID) -> Int? {
        cards.firstIndex(where: { $0.id == id })
    }
}
