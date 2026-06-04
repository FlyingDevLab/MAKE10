//
//  MakeTenContentView.swift
//  FDL-TenBlitz
//
//  Created by 空飛ぶ研究室(FlyingDevLab) on 2026/03/08.
//

import SwiftUI

// MARK: - Screen

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

    @State private var viewModel        = GameViewModel()
    @State private var hasAgreedToTerms = UserDefaults.standard.bool(forKey: UDKey.hasAgreedToTerms)
    @State private var screen: Screen   = .make10

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
                case .janken:
                    JankenView()
                        .transition(.opacity)
                case .stickerStorage:
                    StickerStorageView()
                        .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.3), value: screenID)

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
        case .whackAMole, .maze, .pinball, .coinDrop,
             .janken, .stickerStorage:
            return false
        default:
            return true
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
        case .janken:              return String(localized: "janken_title")
        case .stickerStorage:      return String(localized: "sticker_storage_title")
        }
    }

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

    // MARK: - MAKE10 Content

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
