//
//  TitleView.swift
//  FDL-TenBlitz
//
//  Created by 空飛ぶ研究室(FlyingDevLab) on 2026/03/08.
//

// タイトル画面のルートビュー。
// ゲーム選択グリッドを管理する。
//
// ★ このファイルの構成 ★
//   TitleView（親） … pickerRows で組み立てた「行」を縦に並べる独自レイアウト。
//                     フリック操作で並べ替え・吹き飛ばしができ、
//                     無操作が続くと自動デモ（スワップ／フライ）が動く。
//                     デモでは指（👆）がカードの上をスワイプし、それに合わせてカードが動く。
//
// 役割分担:
//   - GamePickerTile (GamePickerComponents.swift) : タップ/フリックの「判定」
//   - TitleView（このファイル）                    : フリックの「処理」（スワップ・吹き飛ばし・デモ）
//   - GameRankManager                              : 並び順の永続化
//   - MakeTenContentView                           : タイル選択後の画面遷移・ゲーム開始
//
// ★ 旧バージョンからの変更点 ★
//   「30びょう」「10びょう」の ModeButton と「その他ゲーム」ボタンを廃止し、
//   全ゲームを統一サイズの GamePickerTile で2列グリッドに並べた。
//   フリック操作で並び替えができ、並び順は GameRankManager が UserDefaults に永続化する。
//   blitz（10びょう）は isBlitzUnlocked が true になるまで非表示にする。
//   FDLロゴのアニメーションカード（数式ループ演出）は廃止し、
//   ロゴ＋回転リングだけの GamePickerSelection.logoCard として
//   ゲーム選択の一員に統合した。ただし見た目は画面幅いっぱいのバナーにしたため、
//   均等2列を前提にした LazyVGrid をやめ、pickerRows による自前の行組み立てに変更した。
//
// ★ バナー（logoCard）のフリック挙動について ★
//   ・左右フリック → 相手がいないため自動的に「末尾送り」になる（特別なコードは不要）
//   ・上下フリック → 隣接行があれば3点ローテーション、無ければ（画面の端）末尾送りへ合流する
//     （GameRankManager.rotateBanner を参照）
//   ・通常タイルがバナーへ向けて縦フリック → 単純な1対1位置入れ替え（既存の swap を流用）。
//     入れ替わった側で相棒を失ったタイルは、自動的に「片方だけの行」になる。
//
// ★ 表示枚数の可変化について ★
//   バナーが先頭 visibleCountWithBanner 枠以内にあるときは「バナー＋通常8枚」、
//   それより後ろ（左右フリックで最後尾に送られた等）にあるときは
//   「バナー抜きで通常10枚」に切り替わる。currentVisibleCount / visibleGames を参照。
//
// ★ タイル移動のアニメーションについて ★
//   matchedGeometryEffect（tileTransition名前空間）で各タイルにゲームIDを紐付けている。
//   これにより、行（HStack）をまたいだ移動（スワップで左右が入れ替わる、末尾送り、
//   バナーローテーションなど）でも「同じタイルがどこからどこへ動いたか」を
//   SwiftUI が追跡でき、位置の変化が自動的に滑らかなアニメーションになる。
//
// このファイルでは「世代番号パターン」を使っている（demoGeneration）。
// パターンの解説は GameViewModel.swift を参照。

import SwiftUI

// MARK: - TitleView

struct TitleView: View {

    // MARK: 依存（呼び出し側から渡すパラメータ）

    var viewModel:    GameViewModel
    /// true のあいだは自動デモを止める。上にお知らせ・休憩のカードが重なっているときに使う
    /// （カードの後ろでデモの指が動くと、カードの指と2本になってまぎらわしいため）。
    var pausesDemo: Bool = false
    /// タイルがタップされたときに呼ばれるコールバック。
    /// MakeTenContentView が画面遷移・ゲーム開始を担う。
    var onSelectGame: (GamePickerSelection) -> Void

    // MARK: ゲームグリッド状態

    /// ゲームタイルの並び順を管理する（UserDefaults に永続化）。
    @State private var rankManager = GameRankManager()
    /// 末尾送り演出中のタイルのフライオフセット（キー: ゲーム、値: 飛ぶ方向）。
    @State private var flyOffsets: [GamePickerSelection: CGSize] = [:]

    /// フリックと判定する最低速度（pt/s）。
    private let flickSpeedThreshold: CGFloat = 300   // ← 変更可

    /// バナーが表示される場合の表示枚数（バナー1 + 通常8 = 9）。
    private let visibleCountWithBanner: Int = 9      // ← 変更可
    /// バナーが表示されない場合の表示枚数（通常タイルのみ10）。
    private let visibleCountWithoutBanner: Int = 10  // ← 変更可

    /// バナー（logoCard）の高さ。画面幅いっぱいでも正方形に伸びないよう明示的に固定する。
    /// 他タイルの実測高さと見比べて合わなければここだけ調整すればよい。
    private let bannerHeight: CGFloat = 130          // ← 変更可

    /// 自動デモアニメの世代番号。手動操作時にインクリメントしてデモを停止する。
    @State private var demoGeneration: Int = 0

    // MARK: デモの指（👆）

    // ★ なぜ指を出すのか ★
    //   カードを勝手に動かすだけでは「指で動かせる」ことに気づかない人が多かった。
    //   指がカードをスワイプし、その動きに合わせてカードが動くことで、操作方法そのものを見せる。

    /// 各タイルの位置（グリッドの座標系）。デモの指をどのカードの上に出すかを決めるのに使う。
    @State private var tileFrames: [GamePickerSelection: CGRect] = [:]
    /// 指の位置（指先の位置。グリッドの座標系）。
    @State private var fingerPoint: CGPoint = .zero
    /// 指を表示しているか。
    @State private var fingerVisible = false
    /// 指で押しているか（押すと少し小さくなる）。
    @State private var fingerPressed = false

    /// グリッドの座標系の名前。タイルの位置と指の位置を同じ基準で扱うために使う。
    private let gridSpace = "titleGrid"

    /// タイルの位置移動（スワップ・末尾送り・バナーローテーション）を滑らかにアニメーションさせるための名前空間。
    /// matchedGeometryEffect は「同じ id を持つビューが前後でどこにあったか」を追跡して
    /// フレーム差分を自動でアニメーションする仕組みで、行（HStack）をまたいだ移動にも対応できる。
    @Namespace private var tileTransition

    // MARK: 横長の画面での並べ方

    // ★ 横長のときは、行と列を入れ替えて並べる ★
    //   縦長のとき:  ロゴは「上の1行」、2枚組は「横に2枚」、行が上から下へ並ぶ。
    //   横長のとき:  ロゴは「左の1列」、2枚組は「縦に2枚」、列が左から右へ並ぶ。
    //   並び順と、となり合うカードの関係はそのままなので、画面を回しても「どこに何があるか」が変わりにくい。
    //   また横長では2段だけになるので、iPad を横にしたときや高さの低いウィンドウでも、上下にはみ出さない。
    //
    // ★ フリックの向きも入れ替える理由 ★
    //   縦長で「右へフリック＝となりと入れ替え」だった動きは、横長では「下へフリック」になる。
    //   指の動きの縦と横を入れ替えてから（transposed）いつもの handleFlick の判定に渡せば、
    //   並べ替えの仕組み（GameRankManager）や判定の中身を変えずに、横長でも同じように並べ替えられる。
    //
    // どちらの並べ方にするかは、端末の向きではなく「使える場所が横長かどうか」で決める（DS.isWide）。

    /// 一覧を置ける場所の大きさ（回転・分割表示・Duo の開閉のたびに測り直す）。
    @State private var areaSize: CGSize = .zero

    /// 横長の並べ方（行と列を入れ替える）にするか。
    private var isWideLayout: Bool { DS.isWide(areaSize) }

    /// 行（縦長）／列（横長）を並べる向き。AnyLayout にすると、切り替えてもカードが同じものとして扱われ、滑らかに動く。
    private var lineLayout: AnyLayout {
        isWideLayout ? AnyLayout(HStackLayout(spacing: 10)) : AnyLayout(VStackLayout(spacing: 10))
    }

    /// 2枚組の中で2枚を並べる向き（縦長は横に2枚、横長は縦に2枚）。
    private var pairLayout: AnyLayout {
        isWideLayout ? AnyLayout(VStackLayout(spacing: 10)) : AnyLayout(HStackLayout(spacing: 10))
    }

    // MARK: body

    var body: some View {
        VStack(spacing: 0) {

            // ── ゲーム選択グリッド（行ベース。横長のときは列ベース） ──
            lineLayout {
                ForEach(Array(pickerRows.enumerated()), id: \.element.id) { rowIndex, row in
                    switch row {
                    case .banner(let game):
                        GamePickerTile(
                            game:      game,
                            flyOffset: flyOffsets[game] ?? .zero
                        ) {
                            onSelectGame(game)
                        } onFlick: { translation, velocity in
                            handleFlick(
                                game:        game,
                                rowIndex:    rowIndex,
                                column:      nil,
                                translation: screenToGrid(translation),
                                velocity:    screenToGrid(velocity)
                            )
                        }
                        .matchedGeometryEffect(id: game, in: tileTransition)
                        // 縦長は「高さ」、横長は「幅」を bannerHeight に固定する（横長ではロゴが左の1列になるため）
                        .frame(width:  isWideLayout ? bannerHeight : nil,
                               height: isWideLayout ? nil : bannerHeight)
                        .modifier(TileFrameReporter(game: game, space: gridSpace) { tileFrames[$0] = $1 })

                    case .pair(let left, let right):
                        pairLayout {
                            GamePickerTile(
                                game:      left,
                                flyOffset: flyOffsets[left] ?? .zero
                            ) {
                                onSelectGame(left)
                            } onFlick: { translation, velocity in
                                handleFlick(
                                    game:        left,
                                    rowIndex:    rowIndex,
                                    column:      0,
                                    translation: screenToGrid(translation),
                                    velocity:    screenToGrid(velocity)
                                )
                            }
                            .matchedGeometryEffect(id: left, in: tileTransition)
                            .modifier(TileFrameReporter(game: left, space: gridSpace) { tileFrames[$0] = $1 })

                            if let right {
                                GamePickerTile(
                                    game:      right,
                                    flyOffset: flyOffsets[right] ?? .zero
                                ) {
                                    onSelectGame(right)
                                } onFlick: { translation, velocity in
                                    handleFlick(
                                        game:        right,
                                        rowIndex:    rowIndex,
                                        column:      1,
                                        translation: screenToGrid(translation),
                                        velocity:    screenToGrid(velocity)
                                    )
                                }
                                .matchedGeometryEffect(id: right, in: tileTransition)
                                .modifier(TileFrameReporter(game: right, space: gridSpace) { tileFrames[$0] = $1 })
                            } else {
                                // 奇数個であぶれた行の空きマス（見た目にも操作にも影響しない透明マス）
                                Color.clear
                            }
                        }
                    }
                }
            }
            // ← 変更可：グリッド再配置アニメ（スワップの半速に合わせて response を 0.80 に）
            .animation(.spring(response: 0.80, dampingFraction: 0.8), value: visibleGames)
            .coordinateSpace(name: gridSpace)
            // デモの指。カードより手前に重ね、タップは下のカードへ素通しさせる
            .overlay(alignment: .topLeading) { demoFinger }
            .padding(.horizontal, 24)   // 他画面（遊び方カード等）と揃えた余白
            .padding(.bottom, 24)
        }
        .onGeometryChange(for: CGSize.self) { proxy in
            proxy.size
        } action: { size in
            areaSize = size
        }
        .onAppear {
            // デモで見た目だけ動いていた並びを捨て、保存済みの（自分で並べた）順番に戻す
            rankManager.reloadSaved()
            // ← 変更可：初回デモ開始までの待機時間（秒）
            scheduleDemo(delay: 2.5)
        }
        .onChange(of: pausesDemo) { _, paused in
            if paused {
                stopDemo()
            } else {
                scheduleDemo(delay: 2.5)
            }
        }
        .onDisappear {
            // 世代番号を進めて、予約済みのデモをすべて無効にする（ゲーム中に裏で動かさない）
            demoGeneration += 1
            fingerVisible  = false
            fingerPressed  = false
        }
    }

    // MARK: デモの指

    /// 指先の大きさ（pt）。← 変更可
    private let fingerSize: CGFloat = 52

    /// デモでカードをスワイプする指。fingerPoint に指先が来るよう、絵文字を少し下にずらして置く。
    private var demoFinger: some View {
        Text(verbatim: "👆")
            .font(.system(size: fingerSize))
            .shadow(color: .black.opacity(0.25), radius: 4, x: 0, y: 3)
            .scaleEffect(fingerPressed ? 0.85 : 1.0, anchor: .top)
            .position(x: fingerPoint.x, y: fingerPoint.y + fingerSize * 0.5)
            .opacity(fingerVisible ? 1 : 0)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    /// 指でカードをスワイプする演出を1回行う。
    ///   ① from に指を出す → ② 押す → ③ to へ動かす（同時に action でカードを動かす）→ ④ 離して消える
    /// 途中で世代が変わったら（＝ユーザーが触ったら）そこでやめる。
    /// - Parameters:
    ///   - action: 指が動き出す瞬間に呼ぶ。カードを動かす処理を渡す。
    ///   - completion: 指が消え終わったあとに呼ぶ。
    private func demoSwipe(
        generation: Int,
        from: CGPoint,
        to: CGPoint,
        action: @escaping () -> Void,
        completion: @escaping () -> Void
    ) {
        // ← 変更可：指の演出の各段階の時間（秒）
        let appear: Double = 0.30
        let press:  Double = 0.15
        let move:   Double = 0.55
        let leave:  Double = 0.30
        let pressHold: Double = press + 0.05

        fingerPoint = from
        withAnimation(.easeOut(duration: appear)) { fingerVisible = true }

        DispatchQueue.main.asyncAfter(deadline: .now() + appear) {
            guard generation == self.demoGeneration else { return }
            withAnimation(.easeInOut(duration: press)) { self.fingerPressed = true }

            DispatchQueue.main.asyncAfter(deadline: .now() + pressHold) {
                guard generation == self.demoGeneration else { return }
                withAnimation(.easeInOut(duration: move)) { self.fingerPoint = to }
                action()

                DispatchQueue.main.asyncAfter(deadline: .now() + move) {
                    guard generation == self.demoGeneration else { return }
                    withAnimation(.easeOut(duration: leave)) {
                        self.fingerPressed = false
                        self.fingerVisible = false
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + leave) {
                        guard generation == self.demoGeneration else { return }
                        completion()
                    }
                }
            }
        }
    }

    // MARK: 表示ゲームの算出

    /// blitz の解放状態を反映した、ロゴを含む全ゲームの並び順。
    /// visibleGames / currentVisibleCount の両方から参照される共通の下地。
    private var filteredGames: [GamePickerSelection] {
        rankManager.sortedGames.filter { $0 != .blitz || viewModel.isBlitzUnlocked }
    }

    /// 現在の表示枚数上限。ロゴの位置によって9（バナーあり）と10（バナーなし）を動的に切り替える。
    /// ⚠️ 変更注意: handleFlick / runDemoFly の「hasHiddenGame」判定もこの値を参照するため、
    ///   枚数を変えるときは visibleCountWithBanner / visibleCountWithoutBanner の定数だけを書き換えること。
    private var currentVisibleCount: Int {
        let filtered = filteredGames
        guard let bannerIndex = filtered.firstIndex(of: .logoCard) else {
            return visibleCountWithoutBanner
        }
        return bannerIndex < visibleCountWithBanner ? visibleCountWithBanner : visibleCountWithoutBanner
    }

    /// グリッドに表示するゲーム一覧。
    /// ロゴが先頭 visibleCountWithBanner 枠以内にあれば「ロゴ＋通常8枚」をそのまま上位9個として表示し、
    /// それより後ろ（左右フリックで最後尾に送られた等）にあれば、ロゴを除外して通常タイル上位10個を表示する。
    private var visibleGames: [GamePickerSelection] {
        let filtered = filteredGames
        guard let bannerIndex = filtered.firstIndex(of: .logoCard) else {
            return Array(filtered.prefix(visibleCountWithoutBanner))
        }
        if bannerIndex < visibleCountWithBanner {
            return Array(filtered.prefix(visibleCountWithBanner))
        } else {
            return Array(filtered.filter { $0 != .logoCard }.prefix(visibleCountWithoutBanner))
        }
    }

    // MARK: 行の組み立て

    /// グリッド描画用の1行。banner は画面幅いっぱいの単独行、pair は通常タイル2枚組の行。
    /// 奇数個で組めなかった最後の1枚は right が nil になり、空きマスとして描画される。
    private enum PickerRow: Identifiable {
        case banner(GamePickerSelection)
        case pair(left: GamePickerSelection, right: GamePickerSelection?)

        /// 行の中身から作る安定したID。
        /// ⚠️ 変更注意: これが配列上の位置（offset）ではなく中身ベースであることで、
        ///   SwiftUI が「同じ行が別の位置へ移動した」と認識できるようになる。
        ///   ただし .pair はタイル自体の入れ替わりでこのIDが変わってしまうため、
        ///   タイル単位の移動アニメーションは matchedGeometryEffect（tileTransition）が別途担っている。
        var id: String {
            switch self {
            case .banner(let game):
                return "banner-\(game.rawValue)"
            case .pair(let left, let right):
                return "pair-\(left.rawValue)-\(right?.rawValue ?? "_")"
            }
        }
    }

    /// visibleGames を順に走査し、logoCard を単独のフル幅行に、それ以外を2枚組の行に組み立てる。
    /// ⚠️ 変更注意: バナー（logoCard）がどの位置に来ても、その位置で単独行として割り込む。
    ///   直前が奇数個で終わっていた場合、バナーの手前の1枚は right: nil の空きマス行になる
    ///   （繰り上げて詰めるのではなく、あえて空けている＝バナーの位置が動いても手前の並びを崩さない）。
    private var pickerRows: [PickerRow] {
        var rows: [PickerRow] = []
        var i = 0
        let games = visibleGames
        while i < games.count {
            let game = games[i]
            if game == .logoCard {
                rows.append(.banner(game))
                i += 1
            } else if i + 1 < games.count, games[i + 1] != .logoCard {
                rows.append(.pair(left: game, right: games[i + 1]))
                i += 2
            } else {
                rows.append(.pair(left: game, right: nil))
                i += 1
            }
        }
        return rows
    }

    // MARK: 自動デモアニメ

    // ★ 自動デモの動きを保存しない理由 ★
    //   以前はデモの入れ替えも手で並べ替えたときと同じく保存していた。そのため、
    //   ・何もしないでいるだけで、自分で並べた順番が少しずつ書き換わる
    //   ・ゲームを始めてもデモが裏で動き続け、戻ると並びが変わっている
    //   ・「入れ替えて元に戻す」の途中でゲームを始めると、戻らないまま保存される
    //   という不具合があった。デモは見た目だけにして、保存するのは手で並べ替えたときだけにする。
    //   画面を離れたら onDisappear で世代番号を進めてデモを止め、戻ってきたときは保存済みの
    //   （＝自分で並べた）順番から表示し直す。

    /// デモを（再）スケジュールする。
    /// 手動操作後も delay 秒の無操作が続けば自動デモが再開される。
    /// demoGeneration をインクリメントすることで古い世代のコールバックを無効化する。
    private func scheduleDemo(delay: Double) {
        stopDemo()
        let gen = demoGeneration
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            // カードが重なっているあいだは始めない（カードが閉じたら onChange でまた予約される）
            guard !self.pausesDemo else { return }
            runDemoLoop(generation: gen)
        }
    }

    /// 進行中・予約済みのデモをすべて止め、出ていた指を引っ込める。
    private func stopDemo() {
        demoGeneration += 1
        withAnimation(.easeOut(duration: 0.2)) {
            fingerVisible = false
            fingerPressed = false
        }
    }

    /// スワップデモとフライデモをランダムで切り替えながらループする。
    /// ⚠️ バナー（logoCard）は対象から除外する。行の形（単独行 vs 2枚組）が異なるタイル同士を
    ///   機械的に交換すると見た目が破綻するため、常に通常タイルの中だけで完結させる。
    private func runDemoLoop(generation: Int) {
        guard generation == demoGeneration else { return }
        let candidates = visibleGames.filter { $0 != .logoCard }
        guard candidates.count >= 2 else { return }

        if Bool.random() {
            runDemoSwap(generation: generation, candidates: candidates)
        } else {
            runDemoFly(generation: generation, candidates: candidates)
        }
    }

    /// 末尾2枚（バナーを除く）を入れ替えて戻すデモ。
    /// 指が左のカードを右へスワイプして入れ替え → 少し待って、指が右へ移ったカードを左へスワイプして戻す
    /// → 4秒後に次のデモへ。
    private func runDemoSwap(generation: Int, candidates: [GamePickerSelection]) {
        let lastGame   = candidates[candidates.count - 1]
        let secondLast = candidates[candidates.count - 2]

        guard let fromFrame = tileFrames[secondLast],
              let toFrame   = tileFrames[lastGame] else {
            // まだ位置が分からない（表示直後など）ときは、少し待ってからやり直す
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                self.runDemoLoop(generation: generation)
            }
            return
        }

        // ① secondLast を lastGame の位置へスワイプして入れ替える
        demoSwipe(
            generation: generation,
            from: center(of: fromFrame),
            to:   center(of: toFrame),
            action: { self.demoSwap(lastGame, secondLast) },
            completion: {
                // ← 変更可：入れ替えてから戻し始めるまでの待機時間（秒）
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                    guard generation == self.demoGeneration else { return }
                    // ② 移動した secondLast を元の位置へスワイプして戻す
                    self.demoSwipe(
                        generation: generation,
                        from: self.center(of: toFrame),
                        to:   self.center(of: fromFrame),
                        action: { self.demoSwap(lastGame, secondLast) },
                        completion: {
                            // ← 変更可：次のデモまでの待機時間（秒）
                            DispatchQueue.main.asyncAfter(deadline: .now() + 4.0) {
                                self.runDemoLoop(generation: generation)
                            }
                        }
                    )
                }
            }
        )
    }

    /// デモ用の入れ替え（保存しない）。
    private func demoSwap(_ a: GamePickerSelection, _ b: GamePickerSelection) {
        guard let si = rankManager.sortedGames.firstIndex(of: a),
              let sj = rankManager.sortedGames.firstIndex(of: b) else { return }
        // ← 変更可：デモスワップ速度（response: 0.70 = 手動の半速）
        withAnimation(.spring(response: 0.70, dampingFraction: 0.75)) {
            rankManager.swap(at: si, with: sj, persist: false)   // デモは保存しない（上の解説を参照）
        }
    }

    /// 枠の中心。
    private func center(of frame: CGRect) -> CGPoint {
        CGPoint(x: frame.midX, y: frame.midY)
    }

    /// 末尾タイル（バナーを除く）を画面外に飛ばして末尾送りするデモ。
    /// 隠しゲームがあれば新タイルがスライドインして「入れ替わり」を見せられる。
    private func runDemoFly(generation: Int, candidates: [GamePickerSelection]) {
        let lastGame = candidates[candidates.count - 1]

        guard let frame = tileFrames[lastGame] else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                self.runDemoLoop(generation: generation)
            }
            return
        }

        // 指がカードを外側へはらう（縦長は右へ、横長は下へ）。指はカードの端あたりまで動き、カードはそのまま画面の外へ飛んでいく
        let start = center(of: frame)
        let end   = isWideLayout
            ? CGPoint(x: frame.midX, y: frame.maxY)
            : CGPoint(x: frame.maxX, y: frame.midY)   // ← 変更可：指が動く距離
        demoSwipe(
            generation: generation,
            from: start,
            to:   end,
            action: { self.demoFly(lastGame, generation: generation) },
            completion: {}
        )
    }

    /// デモ用の吹き飛ばし（保存しない）。飛び終わったら末尾へ送り、次のデモを予約する。
    private func demoFly(_ lastGame: GamePickerSelection, generation: Int) {
        // ← 変更可：デモフライ方向（末尾のタイルは外側の端にあるので、縦長は右へ・横長は下へ）
        let flyDir = gridToScreen(CGSize(width: 600, height: 0))

        // ← 変更可：デモフライ速度（duration: 0.44 = 手動の半速）
        withAnimation(.easeIn(duration: 0.44)) {
            flyOffsets[lastGame] = flyDir
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.50) {
            // ⚠️ 後始末（flyOffsets の除去）は世代に関係なく必ず行うこと。
            //   guard の後に書くと、デモ中にユーザーが操作した場合（＝世代が進んだ場合）に
            //   タイルが画面外へ取り残され、再起動するまでグリッドに空白が残るバグになる。
            guard generation == self.demoGeneration else {
                withAnimation(.spring(response: 0.40, dampingFraction: 0.80)) {
                    _ = self.flyOffsets.removeValue(forKey: lastGame)
                }
                return
            }

            let allVisible    = filteredGames
            let hasHiddenGame = allVisible.count > currentVisibleCount

            flyOffsets.removeValue(forKey: lastGame)
            if hasHiddenGame {
                // ← 変更可：新タイルのスライドイン速度（response: 0.80 = 手動の半速）
                withAnimation(.spring(response: 0.80, dampingFraction: 0.75)) {
                    rankManager.throwToBottom(lastGame, persist: false)
                }
            } else {
                rankManager.throwToBottom(lastGame, persist: false)
            }

            // ← 変更可：フライ後、次のデモまでの待機時間（秒）
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                self.runDemoLoop(generation: generation)
            }
        }
    }

    // MARK: 向きの読み替え（横長の並べ方用）

    /// 画面上の指の動きを、縦長の並べ方での向きに直す。横長のときだけ縦と横を入れ替える。
    private func screenToGrid(_ size: CGSize) -> CGSize {
        isWideLayout ? CGSize(width: size.height, height: size.width) : size
    }

    /// 縦長の並べ方での向きを、画面上の向きに戻す。縦と横の入れ替えは、2回行うと元に戻る。
    private func gridToScreen(_ size: CGSize) -> CGSize {
        screenToGrid(size)
    }

    // MARK: フリック処理

    /// フリックの方向から「同じ行・同じ列に相手がいればスワップ」「いなければ末尾送り」を判定する。
    /// バナー（column == nil）の縦フリックは、隣接行があれば別処理（3点ローテーション）で完結し、
    /// 隣接行が無ければ（画面の端）下の共通の末尾送り処理へ合流する。
    ///
    /// ★ 行ベースになったことでの考え方の変化 ★
    ///   以前は「2列固定グリッドの通し番号」で隣を計算していたが、バナーが不定形（単独行）を
    ///   挟むようになったため、pickerRows（行の配列）を都度引いて「同じ行の反対列」
    ///   「隣接行の同じ列」を探す方式に変えた。相手が見つからない場合（行の端・外向きフリック・
    ///   隣接行が存在しない）は、すべて同じ「末尾送り」処理に合流する。
    ///
    /// ★ 通常タイル ⇄ バナーの縦フリックについて ★
    ///   隣接行がバナー（単独行）のときは、その1枚だけを相手として通常の swap を呼ぶ。
    ///   結果として、入れ替わった側で相棒を失ったタイルは自動的に「片方だけの行」になる
    ///   （pickerRows が「次がlogoCardなら手前を単独扱いにする」ロジックを持っているため）。
    private func handleFlick(
        game:        GamePickerSelection,
        rowIndex:    Int,
        column:      Int?,      // nil = バナー（単独行）、0 = 左、1 = 右
        translation: CGSize,
        velocity:    CGSize
    ) {
        // 三平方の定理で速度ベクトルの大きさを求め、しきい値未満は無視する
        let speed = sqrt(velocity.width * velocity.width + velocity.height * velocity.height)
        guard speed > flickSpeedThreshold else { return }

        let isHorizontal = abs(translation.width) > abs(translation.height)

        // ── バナーの縦フリック：隣接行があれば3点ローテーション、無ければ末尾送りへ ──────
        // 通常タイルの「相手を探してswap」とは仕組みが異なる（1個 vs 複数個のため）
        // ので、隣接行が見つかった場合だけここで完結させて早期returnする。
        // 画面の端（隣接行が存在しない）は早期returnせず、下の共通の末尾送り処理へ合流させる。
        if column == nil, !isHorizontal {
            let rows              = pickerRows
            let neighborRowIndex  = translation.height > 0 ? rowIndex + 1 : rowIndex - 1
            if rows.indices.contains(neighborRowIndex),
               case .pair(let nLeft, let nRight) = rows[neighborRowIndex],
               let bannerIdx = rankManager.sortedGames.firstIndex(of: game) {

                let rowGames   = [nLeft, nRight].compactMap { $0 }
                let rowIndices = rowGames.compactMap { rankManager.sortedGames.firstIndex(of: $0) }

                if !rowIndices.isEmpty {
                    // 手動操作でデモを一時停止し、5秒後に再開する
                    scheduleDemo(delay: 5.0)

                    SoundManager.shared.vibrate()
                    // ← 変更可：バナーのローテーション速度
                    withAnimation(.spring(response: 0.70, dampingFraction: 0.75)) {
                        rankManager.rotateBanner(
                            at:        bannerIdx,
                            withRow:   rowIndices,
                            direction: translation.height > 0 ? .down : .up
                        )
                    }
                    return
                }
            }
            // ここに到達するのは画面の端（一番上で上フリック／一番下で下フリック）のときだけ。
            // 隣接行が無いので、下の共通処理（末尾送り）へそのまま流れる。
        }

        // 手動操作でデモを一時停止し、5秒後に再開する
        // ← 変更可：無操作からデモ再開までの待機時間（秒）
        scheduleDemo(delay: 5.0)

        let rows = pickerRows
        var neighbor: GamePickerSelection? = nil

        if isHorizontal {
            // 横フリック：内側向き（左タイルを右へ／右タイルを左へ）のときだけ相手あり＝スワップ。
            // 外側向き（左タイルを左へ／右タイルを右へ）は相手なし＝末尾送りへ合流する。
            if let column, rows.indices.contains(rowIndex),
               case .pair(let left, let right) = rows[rowIndex] {
                if column == 0, translation.width > 0, let right {
                    neighbor = right
                } else if column == 1, translation.width < 0 {
                    neighbor = left
                }
            }
        } else {
            // 縦フリック：隣接行が「通常タイルの行（同じ列に相手がいる）」か「バナーの単独行」
            // であればスワップ。それ以外（隣接行が存在しない等）は末尾送りへ合流する。
            let neighborRowIndex = translation.height > 0 ? rowIndex + 1 : rowIndex - 1
            if rows.indices.contains(neighborRowIndex) {
                switch rows[neighborRowIndex] {
                case .pair(let nLeft, let nRight):
                    if let column {
                        neighbor = (column == 0) ? nLeft : nRight
                    }
                case .banner(let bannerGame):
                    // 通常タイル1枚とバナーの単純な1対1入れ替え
                    neighbor = bannerGame
                }
            }
        }

        if let neighbor,
           let si = rankManager.sortedGames.firstIndex(of: game),
           let sj = rankManager.sortedGames.firstIndex(of: neighbor) {
            // ── 相手が見つかった → スワップ ──────────────────
            // ← 変更可：スワップアニメ速度（response: 0.70 = 旧 0.35 の半速）
            withAnimation(.spring(response: 0.70, dampingFraction: 0.75)) {
                rankManager.swap(at: si, with: sj)
            }
        } else {
            // ── 相手がいない（行の端・外向きフリック等）→ 飛ばして末尾送り ──
            // 600pt = どの端末でも画面外まで確実に出る距離
            let flyDir: CGSize
            if isHorizontal {
                flyDir = translation.width > 0
                    ? CGSize(width: 600, height: 0)
                    : CGSize(width: -600, height: 0)
            } else {
                flyDir = translation.height > 0
                    ? CGSize(width: 0, height: 600)
                    : CGSize(width: 0, height: -600)
            }

            SoundManager.shared.vibrate()
            // ← 変更可：飛び出しアニメ速度（duration: 0.44 = 旧 0.22 の半速）
            withAnimation(.easeIn(duration: 0.44)) {
                flyOffsets[game] = gridToScreen(flyDir)   // 判定は縦長の向きで行ったので、画面の向きに戻して飛ばす
            }
            // flyOffset 完了後にグリッド再配置（待機時間も飛び出し速度に合わせて延長）
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.50) {
                let allVisible    = filteredGames
                let hasHiddenGame = allVisible.count > currentVisibleCount

                flyOffsets.removeValue(forKey: game)
                if hasHiddenGame {
                    // ← 変更可：throwToBottom 後のグリッド再配置速度（response: 0.80 = 旧 0.40 の半速）
                    withAnimation(.spring(response: 0.80, dampingFraction: 0.75)) {
                        rankManager.throwToBottom(game)
                    }
                } else {
                    rankManager.throwToBottom(game)
                }
            }
        }
    }
}

// MARK: - TileFrameReporter

/// タイルの位置（指定した座標系での枠）を親へ知らせる ViewModifier。
/// TitleView のデモで、指をどのカードの上に出すかを決めるのに使う。
private struct TileFrameReporter: ViewModifier {
    let game:  GamePickerSelection
    let space: String
    let onChange: (GamePickerSelection, CGRect) -> Void

    func body(content: Content) -> some View {
        content.onGeometryChange(for: CGRect.self) { proxy in
            proxy.frame(in: .named(space))
        } action: { frame in
            onChange(game, frame)
        }
    }
}
