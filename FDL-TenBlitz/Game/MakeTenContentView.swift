//
//  MakeTenContentView.swift
//  FDL-TenBlitz
//
//  Created by 空飛ぶ研究室(FlyingDevLab) on 2026/03/08.
//

// アプリのルートView。初回同意ゲートと、全ゲーム間の画面遷移を一手に引き受けるハブ。
// FDL_TenBlitzApp から最初に表示されるのがこのViewで、
// SharedFrame（共通枠）の中身を screen の値に応じて切り替える。
//
// ★ このファイルの構成 ★
//   Screen             … 表示中の画面を表す列挙型（private）
//   MakeTenContentView … 同意ゲート + 画面切り替え + シール/紙吹雪オーバーレイ
//
// 役割分担:
//   - MakeTenContentView : 「どの画面を出すか」の決定と遷移アニメーション
//   - SharedFrame        : ヘッダー・フッター・設定パネルの共通枠
//   - 各ゲームView       : 画面の中身（このファイルは中身に関与しない）
//
// 新しいゲームを追加する手順は GamePickerComponents.swift 冒頭を参照。
// このファイルでの作業は「Screen に case を追加」すること。
// 追加すると body / headerTitle / backAction / dismissAction / screenID の
// 各 switch がコンパイルエラーになるため、漏れなく分岐を足せる（網羅性チェック）。
// stickerBoardVisible だけは default 側に落ちる（＝非表示）ので、
// シールを表示したい画面の場合のみ明示的に追加する。

import SwiftUI

// MARK: - Screen

// ★ 関連値付き enum とは？ ★
//   Swift の enum は case に「値」を持たせられます（関連値 / associated value）。
//   quizPlaying(EmojiQuizViewModel) は「クイズをプレイ中」という状態に加えて
//   「どのカテゴリのクイズか」を ViewModel ごと持ち運べるため、
//   別の状態変数を用意せずに済みます。
//   取り出すときは case .quizPlaying(let vm) のようにパターンマッチで受け取ります。

/// 表示中の画面を表す列挙型。screen プロパティの値で body の中身が切り替わる。
private enum Screen {
    case make10
    case quizHome
    case quizPlaying(EmojiQuizViewModel)
    case whackAMole
    case maze
    case pinball
    case coinDrop
    case janken
    case stickerStorage
}

// MARK: - MakeTenContentView

struct MakeTenContentView: View {

    // MARK: 状態

    /// MAKE10 の頭脳。設定パネル経由のリセットでも使うため、ハブであるこのViewが保持する。
    @State private var viewModel      = GameViewModel()
    /// 現在表示中の画面。
    @State private var screen: Screen = .make10
    // hasAgreedToTerms は AppSettings.shared 経由で参照する。
    // @Observable により body 内での参照が自動追跡され、値が変わると再描画される。

    // MARK: body（同意ゲート）

    var body: some View {
        Group {
            // 初回同意が済むまではゲームを表示せず、ConsentView だけを出す
            if AppSettings.shared.hasAgreedToTerms {
                gameRootView
            } else {
                ConsentView {
                    withAnimation(.easeInOut(duration: 0.4)) {
                        AppSettings.shared.hasAgreedToTerms = true
                        // didSet が自動で UserDefaults に保存する
                    }
                }
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.4), value: AppSettings.shared.hasAgreedToTerms)
    }

    // MARK: ゲーム本体（共通枠 + 画面切り替え + オーバーレイ）

    private var gameRootView: some View {
        ZStack {
            SharedFrame(
                title:           headerTitle,
                onBack:          backAction,
                onDismiss:       dismissAction,
                gameViewModel:   viewModel,
                // 設定パネルを開いている間は MAKE10 のタイマーを止める
                onSettingsOpen:  { viewModel.suspend() },
                onSettingsClose: { viewModel.resume()  }
            ) {
                // screen の値に応じて SharedFrame の中身を切り替える
                switch screen {
                case .make10:
                    make10Content
                case .quizHome:
                    QuizHomeContent(
                        onStart: { vm in
                            withAnimation(.easeInOut(duration: 0.3)) {
                                screen = .quizPlaying(vm)
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
                case .janken:
                    JankenView()
                        .transition(.opacity)
                case .stickerStorage:
                    StickerStorageView()
                        .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.3), value: screenID)

            // シールボード（表示条件は stickerBoardVisible を参照。zIndex はSharedFrameの階層表どおり）
            if stickerBoardVisible {
                StickerBoardView()
                    .ignoresSafeArea()
                    .zIndex(20)
            }

            // 紙吹雪。allowsHitTesting(false) でタップを下のViewへ素通しさせる
            if viewModel.showConfetti {
                ConfettiView(isSpecial: viewModel.score >= 100)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
                    .zIndex(50)
            }
        }
        .onDisappear { viewModel.suspend() }
        .onAppear    { viewModel.resume()  }
        // ★ onReceive / NotificationCenter とは？ ★
        //   iOS がアプリ全体に放送する「お知らせ」（通知）を受け取る仕組みです。
        //   didEnterBackground = ホーム画面に戻った / willEnterForeground = アプリに戻ってきた
        //   の2つを購読し、MAKE10 のタイマーを一時停止・再開しています
        //   （止める理由は GameViewModel.suspend() の解説を参照）。
        .onReceive(NotificationCenter.default.publisher(
            for: UIApplication.didEnterBackgroundNotification)
        ) { _ in viewModel.suspend() }
        .onReceive(NotificationCenter.default.publisher(
            for: UIApplication.willEnterForegroundNotification)
        ) { _ in viewModel.resume() }
    }

    // MARK: シール表示制御
    //
    // ★ オプトイン設計にしている理由 ★
    //   新しいゲームを Screen に追加したとき、意図せずステッカーボードが
    //   表示されてしまう「追加し忘れバグ」を防ぐため。
    //   表示したい画面を明示的に列挙する（デフォルト非表示）。

    /// シールボードを表示する画面かどうか。表示したい画面のみ true を返す。
    private var stickerBoardVisible: Bool {
        switch screen {
        case .make10, .quizHome, .quizPlaying:
            return true
        default:
            return false
        }
    }

    // MARK: ヘッダー構成（タイトル・戻る・閉じる）

    /// SharedFrame のヘッダー中央に出すタイトル。画面ごとのローカライズ済み文字列を返す。
    private var headerTitle: String? {
        switch screen {
        case .make10:              return String(localized: "title_game_name")
        case .quizHome:            return String(localized: "quiz_home_title")
        case .quizPlaying(let vm): return vm.category.title
        case .whackAMole:          return String(localized: "whack_a_mole_title")
        case .maze:                return String(localized: "maze_title")
        case .pinball:             return String(localized: "pinball_title")
        case .coinDrop:            return String(localized: "coindrop_title")
        case .janken:              return String(localized: "janken_title")
        case .stickerStorage:      return String(localized: "sticker_storage_title")
        }
    }

    /// ヘッダー左の「戻る（chevron.left）」の挙動。nil を返すとボタン自体が出ない。
    /// MAKE10 はゲーム中・結果画面のときだけタイトルへ戻れる。
    /// 各ミニゲームからはゲーム選択（.make10 のタイトル）へ戻る。
    private var backAction: (() -> Void)? {
        switch screen {
        case .make10:
            switch viewModel.gameState {
            case .title:              return nil
            case .playing, .finished:
                return {
                    withAnimation(.easeInOut(duration: 0.3)) { viewModel.returnToTitle() }
                }
            }
        case .quizHome:    return nil
        case .quizPlaying:
            return {
                withAnimation(.easeInOut(duration: 0.3)) { screen = .quizHome }
            }
        case .whackAMole, .maze, .pinball, .coinDrop,
             .janken, .stickerStorage:
            return {
                withAnimation(.easeInOut(duration: 0.3)) { screen = .make10 }
            }
        }
    }

    /// ヘッダー左の「閉じる（xmark）」の挙動。クイズのホーム画面のみ × で抜ける。
    /// onBack が優先されるため、両方 non-nil になる画面は作らないこと（SharedFrame 参照）。
    private var dismissAction: (() -> Void)? {
        switch screen {
        case .make10: return nil
        case .quizHome:
            return {
                withAnimation(.easeInOut(duration: 0.3)) { screen = .make10 }
            }
        case .quizPlaying:                                               return nil
        case .whackAMole, .maze, .pinball, .coinDrop,
             .janken, .stickerStorage:                                   return nil
        }
    }

    /// 画面遷移アニメーションのトリガーに使う識別子。
    ///
    /// ★ なぜ String に変換するのか ★
    ///   .animation(value:) には Equatable（== で比較できる型）を渡す必要がありますが、
    ///   Screen は関連値（EmojiQuizViewModel）を持つため、そのままでは比較できません。
    ///   そこで画面を一意に表す String に変換して比較可能にしています。
    ///   クイズはカテゴリ ID まで含めることで、カテゴリ切り替えでもアニメが発火します。
    private var screenID: String {
        switch screen {
        case .make10:              return "make10"
        case .quizHome:            return "quizHome"
        case .quizPlaying(let vm): return "quizPlaying-\(vm.category.id)"
        case .whackAMole:          return "whackAMole"
        case .maze:                return "maze"
        case .pinball:             return "pinball"
        case .coinDrop:            return "coinDrop"
        case .janken:              return "janken"
        case .stickerStorage:      return "stickerStorage"
        }
    }

    // MARK: MAKE10 コンテンツ

    /// MAKE10 本体の画面。gameState に応じてタイトル / プレイ中 / 結果を切り替える。
    /// タイトル画面のタイル選択はここで受け取り、MAKE10 のモード開始か他ゲームへの遷移に振り分ける。
    @ViewBuilder
    private var make10Content: some View {
        switch viewModel.gameState {
        case .title:
            TitleView(
                viewModel: viewModel,
                onSelectGame: { selected in
                    withAnimation(.easeInOut(duration: 0.3)) {
                        switch selected {
                        case .normal:         viewModel.startGame(mode: .normal)
                        case .blitz:          viewModel.startGame(mode: .blitz)
                        case .quiz:           screen = .quizHome
                        case .whackAMole:     screen = .whackAMole
                        case .maze:           screen = .maze
                        case .pinball:        screen = .pinball
                        case .coinDrop:       screen = .coinDrop
                        case .janken:         screen = .janken
                        case .stickerStorage: screen = .stickerStorage
                        }
                    }
                }
            )
            .transition(.opacity)
        case .playing:
            PlayingView(viewModel: viewModel).transition(.opacity)
        case .finished:
            FinishedView(viewModel: viewModel).transition(.opacity)
        }
    }
}
