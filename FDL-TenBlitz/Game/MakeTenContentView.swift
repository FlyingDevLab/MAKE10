//
//  MakeTenContentView.swift
//  FDL-TenBlitz
//
//  Created by 空飛ぶ研究室(FlyingDevLab) on 2026/03/08.
//

// アプリ全体のルートViewであり、画面遷移の司令塔。
// SharedFrameを1つだけ最上位に保ち、表示するコンテンツだけをscreen/gameStateの変化で差し替える。
// 同意画面・MAKE10・クイズホーム・クイズプレイ中・モグラ叩き・迷路・ピンボールを管理する。
//
// ★ このファイルの全体像 ★
//   アプリ起動後にまず表示されるルートViewです。
//   「今どの画面にいるか」を Screen 型で管理し、
//   SharedFrame という共通の枠の中でコンテンツだけを差し替えます。
//
//   構造:
//     MakeTenContentView（ルート）
//       ├ ConsentView         … 初回同意画面（同意済みなら非表示）
//       └ gameRootView        … 同意後のメイン画面
//           ├ SharedFrame     … 共通フレーム（ヘッダー・設定など）
//           │   └ 各ゲームのコンテンツ（Screen 型で切り替え）
//           ├ StickerBoardView … シールボード（一部ゲーム中は非表示）
//           ├ ConfettiView    … 紙吹雪エフェクト
//           └ GamePickerSheet … ゲーム選択シート（ボトムシート）

import SwiftUI

// MARK: - Screen
//
// アプリが今どの画面を表示しているかを表す列挙型。
// MAKE10 内部のゲーム進行（タイトル/プレイ中/終了）は GameViewModel が別途管理しており、
// この enum はアプリレベルの「どのゲームにいるか」だけを担う。
//
// ★ なぜ enum で画面を管理するのか ★
//   Bool フラグを複数使う方法（isShowingQuiz, isShowingMaze...）だと
//   「クイズと迷路を同時に表示する」という矛盾状態が起きえます。
//   enum にすることで「必ず1つの画面だけが active」という制約を型レベルで保証できます。
//
// ★ .quizPlaying(EmojiQuizViewModel) の形について ★
//   enum の case は値を「連れて歩く」ことができます（関連値）。
//   クイズ中はどのカテゴリを選んだかの情報（vm）が必要なため、
//   case 自体にViewModelを持たせることで画面遷移時に渡し忘れを防ぎます。

private enum Screen {
    case make10
    case quizHome
    case quizPlaying(EmojiQuizViewModel)  // 関連値でクイズのVMを持ち歩く
    case whackAMole
    case maze
    case pinball
    case coinDrop
}

// MARK: - MakeTenContentView

struct MakeTenContentView: View {

    /// MAKE10 のゲーム状態を管理するViewModel（バックグラウンド対応も担う）
    @State private var viewModel        = GameViewModel()
    /// ユーザーが利用規約に同意済みかどうか（UserDefaults から起動時に復元）
    @State private var hasAgreedToTerms = UserDefaults.standard.bool(forKey: UDKey.hasAgreedToTerms)
    /// 現在表示中の画面（アプリレベルの画面遷移を管理）
    @State private var screen: Screen   = .make10

    /// ゲーム選択シート（ボトムシート）の表示フラグ
    @State private var showGamePicker   = false

    var body: some View {
        Group {
            if hasAgreedToTerms {
                // 同意済み → メイン画面を表示
                gameRootView
            } else {
                // 未同意 → 同意画面を表示
                // クロージャ内でフラグを true にすると、自動でメイン画面に切り替わる
                ConsentView {
                    UserDefaults.standard.set(true, forKey: UDKey.hasAgreedToTerms)
                    withAnimation(.easeInOut(duration: 0.4)) { hasAgreedToTerms = true }
                }
                .transition(.opacity)  // フェードイン/アウトで切り替える
            }
        }
        // hasAgreedToTerms が変化したときにアニメーションをかける
        .animation(.easeInOut(duration: 0.4), value: hasAgreedToTerms)
    }

    /// 同意後に表示されるメイン画面。SharedFrame を土台に各ゲームを重ねる構成。
    private var gameRootView: some View {
        ZStack {
            // ── SharedFrame（共通フレーム） ───────────────────
            // SharedFrame は「ヘッダー・設定ボタン・背景」を提供する共通の枠組み。
            // コンテンツ（スロット）だけを差し替えることで、どの画面でも同じ見た目を保てる。
            SharedFrame(
                title:           headerTitle,         // 現在の画面名
                onBack:          backAction,           // 戻るボタンの動作（nil なら非表示）
                onDismiss:       dismissAction,        // 閉じるボタンの動作
                gameViewModel:   viewModel,
                onSettingsOpen:  { viewModel.suspend() },  // 設定を開いたらタイマーを止める
                onSettingsClose: { viewModel.resume()  }   // 設定を閉じたらタイマーを再開する
            ) {
                // ── コンテンツスロット（画面ごとに差し替え）──
                switch screen {
                case .make10:
                    make10Content           // MAKE10 内部のタイトル/プレイ中/終了を別途管理
                case .quizHome:
                    QuizHomeContent(
                        onStart: { vm in
                            withAnimation(.easeInOut(duration: 0.3)) {
                                screen = .quizPlaying(vm)  // VMを連れてクイズプレイ画面へ
                            }
                        }
                    )
                    .transition(.opacity)
                case .quizPlaying(let vm):
                    QuizPlayingContent(viewModel: vm)
                        .transition(.opacity)
                case .whackAMole:
                    WhackAMoleView()
                        .transition(.opacity)
                case .maze:
                    MazeGameView()
                        .transition(.opacity)
                case .pinball:
                    PinballView()
                        .transition(.opacity)
                case .coinDrop:
                    CoinDropView()
                        .transition(.opacity)
                }
            }
            // screenID が変わったときにコンテンツ切り替えアニメーションをかける
            .animation(.easeInOut(duration: 0.3), value: screenID)

            // ── シールボード（一部ゲーム中は非表示）────────────
            // モグラ叩き・迷路・ピンボール・コインドロップ中は SpriteKit が全画面を占有するため
            // シールボードが重なってしまう。stickerBoardVisible で制御して非表示にする。
            if stickerBoardVisible {
                StickerBoardView()
                    .ignoresSafeArea()
                    .zIndex(20)  // SharedFrame より手前・紙吹雪より奥に表示
            }

            // ── 紙吹雪エフェクト ─────────────────────────────
            // viewModel.showConfetti が true のときだけ表示する。
            // allowsHitTesting(false) で紙吹雪がタッチを「透過」するようにしている
            // （紙吹雪でボタンが押せなくなるのを防ぐ）
            if viewModel.showConfetti {
                ConfettiView(isSpecial: viewModel.score >= 100)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
                    .zIndex(50)  // 最前面に表示
            }
        }
        // ── ゲーム選択シート（ボトムシート）──────────────────
        // $showGamePicker が true になると下からシートが出てくる
        .sheet(isPresented: $showGamePicker) {
            GamePickerSheet { selected in
                showGamePicker = false
                withAnimation(.easeInOut(duration: 0.3)) {
                    switch selected {
                    case .quiz:       screen = .quizHome
                    case .whackAMole: screen = .whackAMole
                    case .maze:       screen = .maze
                    case .pinball:    screen = .pinball
                    case .coinDrop:   screen = .coinDrop
                    }
                }
            }
            // .fraction(0.55) = 画面高さの55%だけシートを表示する
            .presentationDetents([.fraction(0.55)])
            .presentationDragIndicator(.visible)  // ドラッグインジケーター（グレーのバー）を表示
        }
        // ── ライフサイクル対応 ────────────────────────────────
        .onDisappear { viewModel.suspend() }  // 画面が消えたらタイマーを止める
        .onAppear    { viewModel.resume()  }  // 画面が現れたらタイマーを再開する
        // NotificationCenter でアプリのバックグラウンド/フォアグラウンド切り替えを検知する
        // ★ onReceive とは？ ★
        //   Combine のパブリッシャーからイベントを受け取るモディファイア。
        //   ここでは iOS のシステム通知（アプリ状態の変化）を購読している。
        .onReceive(NotificationCenter.default.publisher(
            for: UIApplication.didEnterBackgroundNotification)
        ) { _ in viewModel.suspend() }
        .onReceive(NotificationCenter.default.publisher(
            for: UIApplication.willEnterForegroundNotification)
        ) { _ in viewModel.resume() }
    }

    // MARK: - Sticker visibility

    /// シールボードを表示するかどうか。SpriteKit ゲーム中は非表示にする。
    private var stickerBoardVisible: Bool {
        switch screen {
        case .whackAMole, .maze, .pinball, .coinDrop: return false
        default:                                       return true
        }
    }

    // MARK: - Header

    /// SharedFrame のヘッダーに表示するタイトル文字列。
    /// String(localized:) で xcstrings から現在の言語設定に応じた翻訳を取得する。
    private var headerTitle: String? {
        switch screen {
        case .make10:              return String(localized: "title_game_name")
        case .quizHome:            return String(localized: "quiz_home_title")
        case .quizPlaying(let vm): return vm.category.title  // クイズは選択したカテゴリ名を表示
        case .whackAMole:          return String(localized: "whack_a_mole_title")
        case .maze:                return String(localized: "maze_title")
        case .pinball:             return String(localized: "pinball_title")
        case .coinDrop:            return String(localized: "coindrop_title")
        }
    }

    /// 戻るボタンが押されたときの動作。nil のときはボタン自体を非表示にする。
    /// ★ (() -> Void)? とは？ ★
    ///   「引数なし・戻り値なしのクロージャ」のオプショナル型。
    ///   nil を返すことで「戻るボタンを表示しない」状態を表現できる。
    private var backAction: (() -> Void)? {
        switch screen {
        case .make10:
            // MAKE10 は「ゲーム中 / 終了後」のときだけ戻るボタンを表示する
            switch viewModel.gameState {
            case .title:              return nil  // タイトル画面には戻るボタン不要
            case .playing, .finished:
                return {
                    withAnimation(.easeInOut(duration: 0.3)) { viewModel.returnToTitle() }
                }
            }
        case .quizHome:    return nil  // クイズホームはゲーム一覧ボタンが代わりに機能する
        case .quizPlaying:
            // クイズプレイ中の戻るボタン → クイズホームに戻る
            return {
                withAnimation(.easeInOut(duration: 0.3)) { screen = .quizHome }
            }
        // モグラ叩き・迷路・ピンボール・コインドロップの戻るボタン → MAKE10 タイトルに戻る
        case .whackAMole, .maze, .pinball, .coinDrop:
            return {
                withAnimation(.easeInOut(duration: 0.3)) { screen = .make10 }
            }
        }
    }

    /// 閉じるボタンが押されたときの動作。現在は quizHome のみ .make10 に戻る。
    private var dismissAction: (() -> Void)? {
        switch screen {
        case .make10: return nil
        case .quizHome:
            return {
                withAnimation(.easeInOut(duration: 0.3)) { screen = .make10 }
            }
        case .quizPlaying: return nil
        case .whackAMole, .maze, .pinball, .coinDrop: return nil
        }
    }

    /// 画面切り替えアニメーションのトリガーになる文字列ID。
    /// SwiftUI の .animation(value:) は Equatable な値しか使えないため、
    /// enum を直接渡せないケース（関連値あり）では String に変換して比較する。
    private var screenID: String {
        switch screen {
        case .make10:              return "make10"
        case .quizHome:            return "quizHome"
        case .quizPlaying(let vm): return "quizPlaying-\(vm.category.id)"  // カテゴリごとに一意にする
        case .whackAMole:          return "whackAMole"
        case .maze:                return "maze"
        case .pinball:             return "pinball"
        case .coinDrop:            return "coinDrop"
        }
    }

    // MARK: - MAKE10 Content

    /// MAKE10 内部のゲーム進行（タイトル/プレイ中/終了）を GameViewModel.gameState で切り替える。
    /// @ViewBuilder を付けることで switch の各 case で異なる View を返せる。
    /// ★ @ViewBuilder とは？ ★
    ///   複数の View を返せるクロージャ・プロパティを作るためのアノテーション。
    ///   通常の関数は1つの値しか返せないが、@ViewBuilder なら
    ///   if / switch で分岐した複数の View 型を返せる。
    @ViewBuilder
    private var make10Content: some View {
        switch viewModel.gameState {
        case .title:
            TitleView(
                viewModel: viewModel,
                onGamePicker: { showGamePicker = true }  // ゲーム選択シートを開く
            )
            .transition(.opacity)
        case .playing:
            PlayingView(viewModel: viewModel).transition(.opacity)
        case .finished:
            FinishedView(viewModel: viewModel).transition(.opacity)
        }
    }
}

// MARK: - GamePickerSelection
//
// ゲーム選択シートで選択できるゲームの種類を表す列挙型。
// rawValue を UserDefaults の永続化キーとして使うため String 型で定義している。
// CaseIterable に準拠することで新ゲーム追加時も allCases でリスト取得できる。
//
// ★ rawValue に String を使う理由 ★
//   UserDefaults に「何番目のゲームが先頭か」を保存するとき、
//   Int（配列インデックス）だと順番変更のたびに意味が変わってしまいます。
//   String（ゲーム名）なら並び替えても意味が変わらない安定したキーになります。

private enum GamePickerSelection: String, CaseIterable, Hashable {
    case quiz, whackAMole, maze, pinball, coinDrop

    /// ゲーム選択タイルに表示するアイコン絵文字
    var icon: String {
        switch self {
        case .quiz:       return "🎯"
        case .whackAMole: return "🔨"
        case .maze:       return "🗺️"
        case .pinball:    return "🎱"
        case .coinDrop:   return "💰"
        }
    }

    /// ゲーム選択タイルに表示するラベル（多言語対応）
    var label: LocalizedStringKey {
        switch self {
        case .quiz:       return "Quiz"
        case .whackAMole: return "Whack-a-Mole"
        case .maze:       return "Maze"
        case .pinball:    return "Pinball"
        case .coinDrop:   return "CoinDrop"
        }
    }

    /// ゲーム選択タイルのテーマカラー
    var color: Color {
        switch self {
        case .quiz:       return .purple
        case .whackAMole: return .orange
        case .maze:       return .green
        case .pinball:    return .red
        case .coinDrop:   return DS.gold
        }
    }
}

// MARK: - GameRankManager
//
// ゲーム選択シートの並び順を UserDefaults に永続化し、
// フリック操作による並べ替えを管理するクラス。
//
// ★ 並び順を UserDefaults に保存する理由 ★
//   ユーザーがよく遊ぶゲームを一番上に並べた設定を
//   アプリを終了しても記憶するためです。
//   新ゲームを追加するときは allCases に case を1行追加するだけで
//   自動的にリスト末尾に登場します。

@Observable
private final class GameRankManager {

    /// UserDefaults のキー（バージョン番号付きで将来の互換性に備える）
    private static let udKey = "gamePickerRanks_v1"

    /// 現在の並び順（先頭が一番上に表示される）
    var sortedGames: [GamePickerSelection]

    /// UserDefaults から保存済みの並び順を復元する。
    /// 未保存（初回起動）なら allCases のデフォルト順を使う。
    init() {
        let all = GamePickerSelection.allCases
        if let data = UserDefaults.standard.data(forKey: Self.udKey),
           let dict = try? JSONDecoder().decode([String: Int].self, from: data) {
            // 保存済み順序を復元。allCases にある新ゲームは末尾に自動追加される
            // dict[$0.rawValue] ?? 999 → 未登録のゲームは順位999（末尾扱い）
            sortedGames = all.sorted { (dict[$0.rawValue] ?? 999) < (dict[$1.rawValue] ?? 999) }
        } else {
            sortedGames = all  // 初回起動はデフォルト順
        }
    }

    /// 指定のゲームを末尾に送る（グリッド端へのフリック操作に対応）
    func throwToBottom(_ game: GamePickerSelection) {
        sortedGames.removeAll { $0 == game }  // 現在の位置から削除
        sortedGames.append(game)              // 末尾に追加
        save()
    }

    /// 2つのインデックスのゲームを入れ替える（隣接タイルへのフリック操作に対応）
    func swap(at i: Int, with j: Int) {
        // 範囲外アクセスのクラッシュを防ぐためにインデックスを事前チェックする
        guard i >= 0, j >= 0, i < sortedGames.count, j < sortedGames.count else { return }
        sortedGames.swapAt(i, j)
        save()
    }

    /// 現在の並び順を「ゲーム名: 順位」の辞書として JSON エンコードして UserDefaults に保存する
    private func save() {
        var dict: [String: Int] = [:]
        for (index, game) in sortedGames.enumerated() {
            dict[game.rawValue] = index  // rawValue（文字列）をキー、順位をバリューにする
        }
        // JSONEncoder で辞書をバイナリデータに変換してから保存する
        // try? → 失敗してもクラッシュしない（保存できなかった場合は次回起動時にデフォルト順になる）
        if let data = try? JSONEncoder().encode(dict) {
            UserDefaults.standard.set(data, forKey: Self.udKey)
        }
    }
}

// MARK: - GamePickerSheet
//
// ゲーム選択のボトムシート本体。
// LazyVGrid で2列グリッドを表示し、各タイルのフリック操作で並べ替えができる。

private struct GamePickerSheet: View {

    /// ゲームが選択されたときに呼ばれるコールバック
    let onSelect: (GamePickerSelection) -> Void

    /// 並び順を管理するマネージャー
    @State private var rankManager   = GameRankManager()
    /// 縮小アニメーション中のゲーム（末尾に送る演出で一時的に縮小する）
    @State private var shrinkingGame: GamePickerSelection? = nil

    /// フリックと判定する最低速度（pt/s）。これ未満のドラッグはタップとして無視する
    private let flickSpeedThreshold: CGFloat = 300

    var body: some View {
        VStack(spacing: 16) {
            Text("Choose a Game")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            // LazyVGrid: 2列のグリッドレイアウト
            // .flexible() = 利用可能なスペースを均等に分割する列
            // Lazy = 画面に表示されたタイルだけを描画（大量のタイルでもメモリを節約できる）
            LazyVGrid(
                columns: [GridItem(.flexible()), GridItem(.flexible())],
                spacing: 12
            ) {
                // Array(enumerated()) = [(0, .quiz), (1, .whackAMole), ...] のように
                // インデックス付きの配列を作る。フリック方向の計算にインデックスが必要
                ForEach(Array(rankManager.sortedGames.enumerated()), id: \.element) { index, game in
                    GamePickerTile(
                        game: game,
                        isShrinking: shrinkingGame == game  // このタイルが縮小中かどうか
                    ) {
                        onSelect(game)  // タップ時
                    } onFlick: { translation, velocity in
                        handleFlick(
                            game:        game,
                            index:       index,
                            translation: translation,
                            velocity:    velocity
                        )
                    }
                }
            }
            // sortedGames 配列が変わるたびにグリッド全体をスプリングアニメーションで再配置する
            // response: バネの硬さ（小さいほど速い）/ dampingFraction: 振動の収まりやすさ
            .animation(.spring(response: 0.4, dampingFraction: 0.8), value: rankManager.sortedGames)
            .padding(.horizontal, 20)
        }
        .padding(.top, 8)
        .padding(.bottom, 20)
    }

    // MARK: Flick handling

    /// フリックジェスチャーを受け取り、方向と速度から「入れ替え」か「末尾送り」かを判定する。
    private func handleFlick(
        game:        GamePickerSelection,
        index:       Int,
        translation: CGSize,
        velocity:    CGSize
    ) {
        // フリック速度を算出（ベクトルの大きさ = √(vx² + vy²)）
        let speed = sqrt(velocity.width * velocity.width + velocity.height * velocity.height)
        // 閾値未満 = 意図しない微小な動き → 無視する
        guard speed > flickSpeedThreshold else { return }

        // ── 隣接タイルのインデックスを求める ─────────────────
        // 2列グリッドの隣接ルール:
        //   左列（index % 2 == 0）← 左に隣なし、右に index+1
        //   右列（index % 2 == 1）← 左に index-1、右に隣なし
        //   上に index-2、下に index+2（それぞれ範囲内のみ）
        //
        // ★ abs() とは？ ★
        //   絶対値を返す関数。水平方向の移動量と垂直方向の移動量を比べて
        //   どちらが大きいかでフリックの向きを判断している。
        let isHorizontal  = abs(translation.width) > abs(translation.height)
        let count         = rankManager.sortedGames.count
        let neighborIndex: Int?

        if isHorizontal {
            neighborIndex = translation.width > 0
                ? ((index % 2 == 0 && index + 1 < count) ? index + 1 : nil)   // 右フリック
                : ((index % 2 == 1)                      ? index - 1 : nil)   // 左フリック
        } else {
            neighborIndex = translation.height > 0
                ? ((index + 2 < count) ? index + 2 : nil)   // 下フリック
                : ((index >= 2)        ? index - 2 : nil)   // 上フリック
        }

        if let neighbor = neighborIndex {
            // 隣のタイルが存在する → 入れ替え
            withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                rankManager.swap(at: index, with: neighbor)
            }
        } else {
            // フリック方向に隣がない（グリッド端）→ 末尾に送る
            // 先に縮小アニメーションを見せてから並び替えることで「消えて末尾に現れる」演出になる
            SoundManager.shared.vibrate()
            shrinkingGame = game
            // 0.2秒 = 縮小アニメーションが完了するのを待ってから並び替えを実行する
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                shrinkingGame = nil
                withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) {
                    rankManager.throwToBottom(game)
                }
            }
        }
    }
}

// MARK: - GamePickerTile
//
// ゲーム選択グリッドの1つのタイル。
// タップとフリックを1つのジェスチャーで判別する。
//
// ★ タップとフリックをどう区別するか ★
//   DragGesture(minimumDistance: 0) は「指が触れた瞬間から」追跡を開始する。
//   指を離したとき（.onEnded）の移動距離が tapDistanceThreshold 未満なら「タップ」、
//   それ以上なら移動方向・速度も含めて「フリック」として onFlick に渡す。
//   Button を使わずにこの方式にすることで、タップとフリックを1つの view で処理できる。

private struct GamePickerTile: View {

    let game:        GamePickerSelection
    /// このタイルが縮小アニメーション中かどうか（末尾送り演出）
    let isShrinking: Bool
    let onTap:       () -> Void
    let onFlick:     (_ translation: CGSize, _ velocity: CGSize) -> Void

    /// タップとフリックを区別する移動距離の閾値（pt）
    /// 15pt 未満の動きはタップ、以上はフリックとして処理する
    private let tapDistanceThreshold: CGFloat = 15

    /// 押し込み中かどうか（視覚的なフィードバック用）
    @State private var isPressed = false

    var body: some View {
        VStack(spacing: 6) {
            Text(game.icon).font(.largeTitle)
            Text(game.label)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(game.color)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(
            game.color.opacity(0.1),
            in: RoundedRectangle(cornerRadius: DS.tagRadius)
        )
        // ── スケールエフェクト ────────────────────────────────
        // isShrinking（末尾送り演出）と isPressed（押し込みフィードバック）を合成する。
        // 優先度: isShrinking > isPressed > 通常（1.0）
        .scaleEffect(isShrinking ? 0.01 : (isPressed ? 0.94 : 1.0))
        .animation(.easeIn(duration: 0.15),    value: isShrinking)  // 縮小は素早く
        .animation(.easeInOut(duration: 0.1),  value: isPressed)    // 押し込みはやわらかく
        // ── ジェスチャー ─────────────────────────────────────
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    // 指が触れた瞬間から押し込み状態にする（視覚フィードバック）
                    if !isPressed { isPressed = true }
                }
                .onEnded { value in
                    isPressed = false
                    let t        = value.translation
                    // hypot または手動計算でタッチの移動距離を求める
                    let distance = sqrt(t.width * t.width + t.height * t.height)
                    if distance < tapDistanceThreshold {
                        // 移動距離が閾値未満 → タップとして処理
                        SoundManager.shared.vibrate()
                        SoundManager.shared.playTap()
                        onTap()
                    } else {
                        // 移動距離が閾値以上 → フリックとして処理（速度も渡す）
                        onFlick(value.translation, value.velocity)
                    }
                }
        )
    }
}
