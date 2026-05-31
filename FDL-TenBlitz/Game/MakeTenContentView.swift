//
//  MakeTenContentView.swift
//  FDL-TenBlitz
//
//  Created by 空飛ぶ研究室(FlyingDevLab) on 2026/03/08.
//

// アプリ全体のルートViewであり、画面遷移の司令塔。
// SharedFrameを1つだけ最上位に保ち、表示するコンテンツだけをscreen/gameStateの変化で差し替える。
// 同意画面・MAKE10・クイズホーム・クイズプレイ中・モグラ叩き・迷路・ピンボールを管理する。

import SwiftUI

// MARK: - MakeTenContentView

/// どの画面を表示するか
// .make10内のゲーム状態（タイトル/プレイ中/終了）はGameViewModelが管理し、
// このenumはアプリレベルの画面の切り替えを担う
private enum Screen {
    case make10
    case quizHome
    case quizPlaying(EmojiQuizViewModel)
    case whackAMole
    case maze
    case pinball
    case coinDrop
}

struct MakeTenContentView: View {

    @State private var viewModel        = GameViewModel()
    @State private var hasAgreedToTerms = UserDefaults.standard.bool(forKey: UDKey.hasAgreedToTerms)
    @State private var screen: Screen   = .make10

    // その他ゲームのピッカーシート表示フラグ
    @State private var showGamePicker   = false

    var body: some View {
        Group {
            if hasAgreedToTerms {
                gameRootView
            } else {
                ConsentView {
                    UserDefaults.standard.set(true, forKey: UDKey.hasAgreedToTerms)
                    withAnimation(.easeInOut(duration: 0.4)) { hasAgreedToTerms = true }
                }
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.4), value: hasAgreedToTerms)
    }

    private var gameRootView: some View {
        ZStack {
            SharedFrame(
                title:           headerTitle,
                onBack:          backAction,
                onDismiss:       dismissAction,
                gameViewModel:   viewModel,
                onSettingsOpen:  { viewModel.suspend() },
                onSettingsClose: { viewModel.resume()  }
            ) {
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
                }
            }
            .animation(.easeInOut(duration: 0.3), value: screenID)

            // モグラ叩き・迷路・ピンボール中はシールを非表示にする
            if stickerBoardVisible {
                StickerBoardView()
                    .ignoresSafeArea()
                    .zIndex(20)
            }

            if viewModel.showConfetti {
                ConfettiView(isSpecial: viewModel.score >= 100)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
                    .zIndex(50)
            }
        }
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
            .presentationDetents([.fraction(0.55)])
            .presentationDragIndicator(.visible)
        }
        .onDisappear { viewModel.suspend() }
        .onAppear    { viewModel.resume()  }
        .onReceive(NotificationCenter.default.publisher(
            for: UIApplication.didEnterBackgroundNotification)
        ) { _ in viewModel.suspend() }
        .onReceive(NotificationCenter.default.publisher(
            for: UIApplication.willEnterForegroundNotification)
        ) { _ in viewModel.resume() }
    }

    // MARK: - Sticker visibility

    private var stickerBoardVisible: Bool {
        switch screen {
        case .whackAMole, .maze, .pinball, .coinDrop: return false
        default:                           return true
        }
    }

    // MARK: - Header

    private var headerTitle: String? {
        switch screen {
        case .make10:              return String(localized: "title_game_name")
        case .quizHome:            return String(localized: "quiz_home_title")
        case .quizPlaying(let vm): return vm.category.title
        case .whackAMole:          return String(localized: "whack_a_mole_title")
        case .maze:                return String(localized: "maze_title")
        case .pinball:             return String(localized: "pinball_title")
        case .coinDrop:            return String(localized: "coindrop_title")
        }
    }

    private var backAction: (() -> Void)? {
        switch screen {
        case .make10:
            switch viewModel.gameState {
            case .title:             return nil
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
        // モグラ叩き・迷路・ピンボール・コインドロップはMAKE10タイトルに戻る
        case .whackAMole, .maze, .pinball, .coinDrop:
            return {
                withAnimation(.easeInOut(duration: 0.3)) { screen = .make10 }
            }
        }
    }

    private var dismissAction: (() -> Void)? {
        switch screen {
        case .make10:      return nil
        case .quizHome:
            return {
                withAnimation(.easeInOut(duration: 0.3)) { screen = .make10 }
            }
        case .quizPlaying: return nil
        case .whackAMole, .maze, .pinball, .coinDrop: return nil
        }
    }

    private var screenID: String {
        switch screen {
        case .make10:              return "make10"
        case .quizHome:            return "quizHome"
        case .quizPlaying(let vm): return "quizPlaying-\(vm.category.id)"
        case .whackAMole:          return "whackAMole"
        case .maze:                return "maze"
        case .pinball:             return "pinball"
        case .coinDrop:            return "coinDrop"
        }
    }

    // MARK: - MAKE10 Content

    @ViewBuilder
    private var make10Content: some View {
        switch viewModel.gameState {
        case .title:
            // onQuizPicker → onGamePicker に変更（シートを開くだけ）
            TitleView(
                viewModel: viewModel,
                onGamePicker: { showGamePicker = true }
            )
            .transition(.opacity)
        case .playing:
            PlayingView(viewModel: viewModel).transition(.opacity)
        case .finished:
            FinishedView(viewModel: viewModel).transition(.opacity)
        }
    }
}

// MARK: - GamePickerSheet

private enum GamePickerSelection {
    case quiz, whackAMole, maze, pinball, coinDrop
}

private struct GamePickerSheet: View {

    let onSelect: (GamePickerSelection) -> Void

    private let items: [(GamePickerSelection, String, LocalizedStringKey, Color)] = [
        (.quiz,       "🎯", "Quiz",        .purple),
        (.whackAMole, "🔨", "Whack-a-Mole",.orange),
        (.maze,       "🗺️", "Maze",        .green),
        (.pinball,    "🎱", "Pinball",     .red),
        (.coinDrop,   "💰", "CoinDrop",    DS.gold),
    ]

    var body: some View {
        VStack(spacing: 16) {
            Text("Choose a Game")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                ForEach(items, id: \.1) { selection, icon, label, color in
                    Button {
                        onSelect(selection)
                    } label: {
                        VStack(spacing: 6) {
                            Text(icon).font(.largeTitle)
                            Text(label)
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(color)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(color.opacity(0.1), in: RoundedRectangle(cornerRadius: DS.tagRadius))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 20)
        }
        .padding(.top, 8)
        .padding(.bottom, 20)
    }
}
