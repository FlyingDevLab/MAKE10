//
//  EmojiQuizHomeView.swift
//  FDL-TenBlitz
//
//  Created by 空飛ぶ研究室(FlyingDevLab) on 2026/03/08.
//

// 絵文字クイズのホーム画面・プレイ中画面・各UIパーツ（選択肢・進捗・フィードバックなど）を定義するファイル。
// 画面全体のフレーム（SharedFrame）は親View（MakeTenContentView）が管理し、
// このファイルのViewはスクロールコンテンツ部分のみを担当する。
//
// ★ このファイルの構成 ★
//   ── ホーム画面系 ──
//   QuizHomeContent      … ホーム画面本体（モード選択＋カテゴリ選択）
//     ├ QuizSectionCard    … タイトル付きカードコンテナ（両セクションで共用）
//     ├ QuizModeRow        … モード選択行
//     ├ QuizCategoryGroup  … グループ見出し＋カテゴリ行のコンテナ（private）
//     └ QuizCategoryRow    … カテゴリ1件の行（タップで即スタート、private）
//   ── プレイ画面系 ──
//   QuizPlayingContent   … プレイ中画面本体（isFinished で結果画面に切り替え）
//     ├ QuizProgressSection … 問題番号・スコア・進捗ドット
//     │   └ FlexibleDots      … 自動折り返しするドット型進捗（private）
//     ├ QuizQuestionCard    … 問題カード（モード・表示形式で内容を切り替え）
//     ├ QuizChoiceGrid      … 選択肢の2列グリッド
//     │   ├ QuizChoiceButtonState … 選択肢ボタンの表示状態（enum）
//     │   └ QuizChoiceButton      … 選択肢1件のボタン
//     └ QuizFeedbackLabel   … 正解・不正解のフィードバック表示

import SwiftUI

// MARK: - QuizHomeContent

/// カテゴリ選択とモード選択を提供するクイズホーム画面。
/// カテゴリをタップすると即座にゲームが始まる（確認ダイアログなし）。
/// カテゴリデータは onAppear 相当の .task で非同期に読み込む。
struct QuizHomeContent: View {

    // MARK: 依存

    /// ゲーム開始時に ViewModel を親へ渡すコールバック。
    /// QuizHomeContent は VM 生成の責務を持ち、遷移処理は親に委ねる。
    var onStart: (EmojiQuizViewModel) -> Void

    // MARK: ローカル状態

    /// .task で非同期ロードされるカテゴリ一覧。読み込み完了前は ProgressView を表示する。
    @State private var allCategories: [QuizCategory] = []

    /// 選択中のモード（絵文字→テキスト or テキスト→絵文字）を UserDefaults に永続化する。
    ///
    /// ★ @AppStorage とは？ ★
    ///   「UserDefaults への保存」と「@State の自動再描画」を合体させた
    ///   プロパティラッパーです。値を代入すると自動で UserDefaults に保存され、
    ///   値が変わると参照している View が再描画されます。
    ///   View の中で完結する小さな設定値に向いており、キーはタイポ防止のため
    ///   UDKey 経由で指定しています（AppSettings の didSet 方式との使い分け:
    ///   複数画面で共有する設定は AppSettings、1画面ローカルなら @AppStorage）。
    @AppStorage(UDKey.quizMode) private var selectedModeRaw: String = QuizMode.emojiToText.rawValue

    // MARK: 算出プロパティ

    /// 文字列として保存された rawValue を QuizMode 型に変換して返す。
    /// 不正な値が保存されていた場合のフォールバックとして .emojiToText を使う。
    private var selectedMode: QuizMode {
        QuizMode(rawValue: selectedModeRaw) ?? .emojiToText
    }

    /// カテゴリ未選択時のモードラベル表示用に .emoji を固定で使用。
    /// 選択後はカテゴリの displayStyle が QuizPlayingContent 側で適用される。
    private var displayStyle: DisplayStyle { .emoji }

    /// カテゴリをグループ名でまとめ、元の並び順を保ったまま返す。
    /// Set ではなく「出現順でユニーク化」する方式でグループの順番を維持している。
    /// seen.insert($0).inserted は「挿入に成功したか（= 初出か）」を返すため、
    /// filter と組み合わせると“順序を保ったまま重複を除く”定番イディオムになる。
    private var groupedCategories: [(group: String, categories: [QuizCategory])] {
        var seen = Set<String>()
        let groups = allCategories.map(\.group).filter { seen.insert($0).inserted }
        return groups.map { g in (group: g, categories: allCategories.filter { $0.group == g }) }
    }

    // MARK: ゲーム開始

    /// カテゴリをタップしたら即スタート（常に10問ランダム）。
    /// ViewModel を生成して onStart コールバック経由で親に渡す。
    private func startGame(with category: QuizCategory) {
        let vm = EmojiQuizViewModel(category: category, mode: selectedMode, totalCount: 10)   // ← 変更可（出題数）
        onStart(vm)
    }

    // MARK: body

    var body: some View {
        Group {
            // データ未ロード中は ProgressView だけを表示し、レイアウトの乱れを防ぐ
            if allCategories.isEmpty {
                Spacer()
                ProgressView()
                Spacer()
            } else {
                ScrollView {
                    VStack(spacing: 18) {

                        // ── 1. もんだいのしゅるい ────────────────
                        QuizSectionCard(title: String(localized: "quiz_home_section_mode")) {
                            VStack(spacing: 8) {
                                // QuizMode.allCases を列挙してモード選択行を生成する
                                ForEach(QuizMode.allCases, id: \.self) { mode in
                                    QuizModeRow(
                                        mode: mode, displayStyle: displayStyle,
                                        isSelected: selectedMode == mode
                                    ) {
                                        // 選択時にバイブ＋タップ音を再生し、rawValue を AppStorage に保存する
                                        SoundManager.shared.vibrate()
                                        SoundManager.shared.playTap()
                                        selectedModeRaw = mode.rawValue
                                    }
                                }
                            }
                        }

                        // ── 2. カテゴリ（タップで即スタート）──────
                        QuizSectionCard(title: String(localized: "quiz_home_section_category")) {
                            VStack(spacing: 8) {
                                // enumerated() でインデックスを取得し、グループ間に Divider を挿入する
                                ForEach(
                                    Array(groupedCategories.enumerated()),
                                    id: \.element.group
                                ) { idx, grouped in
                                    // 最初のグループの前には Divider を挿入しない
                                    if idx > 0 { Divider().padding(.vertical, 2) }
                                    QuizCategoryGroup(title: grouped.group) {
                                        ForEach(grouped.categories) { cat in
                                            QuizCategoryRow(category: cat) {
                                                startGame(with: cat)
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                    .padding(.bottom, 8)
                }
            }
        }
        // ★ .task とは？ ★
        //   View の表示時に「非同期処理」を始めるためのモディファイアです。
        //   onAppear と似ていますが、(1) async な処理をそのまま書ける
        //   (2) View が消えると実行中の処理が自動でキャンセルされる、という違いがあります
        //   （Task そのものの解説は EmojiQuizViewModel.swift を参照）。
        .task {
            let cats = QuizCategoryLoader.loadAll()
            allCategories = cats
        }
    }
}

// MARK: - QuizPlayingContent

/// ゲームプレイ中の画面。問題カード・選択肢グリッド・フィードバック・次問ボタンを垂直に配置する。
/// isFinished が true になると結果画面（EmojiQuizResultView）に切り替わる。
struct QuizPlayingContent: View {
    var viewModel: EmojiQuizViewModel

    /// カテゴリごとに定義された表示スタイル（絵文字 / コード / テキスト）を参照する。
    private var displayStyle: DisplayStyle { viewModel.category.displayStyle }

    var body: some View {
        Group {
            if viewModel.isFinished {
                // 全問回答完了時に結果画面へ切り替える。
                // 右からスライドインして、フェードアウトで消えるトランジションを設定
                EmojiQuizResultView(viewModel: viewModel)
                    .transition(.asymmetric(
                        insertion: .move(edge: .trailing).combined(with: .opacity),
                        removal:   .opacity
                    ))
            } else if let question = viewModel.currentQuestion {
                // 現在の問題番号（currentIndex）が変わるたびにフェードアニメーションを適用する
                playingContent(question: question)
                    .animation(.easeInOut(duration: 0.25), value: viewModel.currentIndex)
            }
        }
        // isFinished の変化をトリガーに、プレイ中↔結果間のトランジションをアニメーションさせる
        .animation(.easeInOut(duration: 0.35), value: viewModel.isFinished)
    }

    /// プレイ中のメインレイアウト。進捗・問題カード・選択肢・フィードバック・次問ボタンを縦に並べる。
    /// @ViewBuilder で複数の View を条件分岐しながら返せるようにしている
    /// （@ViewBuilder の解説は SharedFrame.swift を参照）。
    @ViewBuilder
    private func playingContent(question: QuizQuestion) -> some View {
        VStack(spacing: 0) {
            // ── 進捗 + 問題カード ─────────────────────────
            VStack(spacing: 8) {
                QuizProgressSection(viewModel: viewModel)
                    .padding(.horizontal, 24)
                QuizQuestionCard(question: question, mode: viewModel.mode, displayStyle: displayStyle)
                    .padding(.horizontal, 24)
            }
            .padding(.top, 8)
            .padding(.bottom, 16)

            // ── 選択肢 + フィードバック ────────────────────
            QuizChoiceGrid(
                question: question, mode: viewModel.mode, displayStyle: displayStyle,
                answerState: viewModel.answerState, selectedItem: viewModel.selectedItem
            ) { viewModel.select($0) }
            .padding(.horizontal, 20)

            QuizFeedbackLabel(
                answerState: viewModel.answerState, correct: question.correct,
                mode: viewModel.mode, displayStyle: displayStyle
            )
            .frame(minHeight: 60)  // フィードバック有無でレイアウトが跳ねないよう最小高さを確保
            .padding(.top, 10)
            .padding(.horizontal, 24)

            // ── 不正解時：つぎのもんだいボタン ──────────────
            // 正解時は自動的に次問に進むため、このボタンは不正解時のみ表示する
            if viewModel.answerState == .wrong {
                Button {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        viewModel.nextQuestion()
                    }
                } label: {
                    Label("quiz_next_question", systemImage: "arrow.right.circle.fill")
                        .font(.system(size: 22, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 18)
                        .background(
                            RoundedRectangle(cornerRadius: DS.btnRadius)
                                .fill(DS.primary)
                                .shadow(color: DS.primary.opacity(0.35), radius: 8, x: 0, y: 4)
                        )
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 24)
                .padding(.top, 8)
                // スケール＋フェードの組み合わせでボタンが自然に現れるよう演出する
                .transition(.scale(scale: 0.85).combined(with: .opacity))
            }

            Spacer()
        }
        // answerState の変化（回答前→正解／不正解）をトリガーにスプリングアニメーションを適用する
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: viewModel.answerState)
    }
}

// MARK: - QuizSectionCard

/// タイトル付きのカードコンテナ。ホーム画面のモード選択・カテゴリ選択の両セクションで共用する。
/// content はジェネリクスで受け取るためどんな View でも格納できる
/// （ジェネリクスと @ViewBuilder の解説は SharedFrame.swift を参照）。
struct QuizSectionCard<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // セクションタイトル。小さめのミュートカラーでセクション区切りとして機能する
            Text(title)
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(DS.muted)
                .tracking(0.5)  // 字間を少し広げて見出しらしい印象にする
            content
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: DS.cardRadius)
                .fill(DS.card)
                .shadow(color: .black.opacity(0.07), radius: 14, x: 0, y: 5)
        )
    }
}

// MARK: - QuizCategoryGroup

/// 同じグループ名に属するカテゴリ行をまとめて表示するコンテナ。
/// グループ名をサブタイトルとして表示し、直下にカテゴリ行を縦並べする。
/// ファイル外から直接参照する必要がないため private で隠蔽している。
private struct QuizCategoryGroup<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            // グループ名は小さくミュートで表示し、主役であるカテゴリ行を引き立てる
            Text(title)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(DS.muted.opacity(0.7))
                .padding(.leading, 4)
            content
        }
    }
}

// MARK: - QuizCategoryRow

/// カテゴリ1件を表示する行コンポーネント。タップで即ゲーム開始する。
/// アイコン・タイトル・問題数を横並びで表示する。
private struct QuizCategoryRow: View {
    let category: QuizCategory
    let action:   () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Text(category.icon)
                    .font(.system(size: 16))
                Text(category.title)
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .foregroundStyle(DS.textPrimary)
                Spacer()
                // カテゴリの総問題数を右端に小さく表示して内容量を伝える
                Text(String(format: String(localized: "quiz_category_item_count"), category.items.count))
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(DS.muted)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: DS.rowRadius)
                    .fill(DS.muted.opacity(0.06))
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - QuizModeRow

/// モード1件を表示する選択行。選択中はプライマリカラーで強調表示する。
/// ホーム画面のモードセクションで ForEach から生成される。
private struct QuizModeRow: View {
    let mode:        QuizMode
    let displayStyle: DisplayStyle
    let isSelected:  Bool
    let action:      () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    // モードの主ラベル（例：「えもじ → ことば」）
                    Text(mode.primaryLabel(for: displayStyle))
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(DS.textPrimary)
                    // モードの補足説明（例：「えもじをみてこたえよう」）
                    Text(mode.descriptionLabel(for: displayStyle))
                        .font(.system(size: 12, weight: .regular, design: .rounded))
                        .foregroundStyle(DS.muted)
                }
                Spacer()
                // 選択中のモードにのみチェックアイコンを表示する
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 17))
                        .foregroundStyle(DS.primary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: DS.rowRadius)
                    // 選択中は薄いプライマリ色で塗り、枠線も付けて選択状態を強調する
                    .fill(isSelected ? DS.primary.opacity(0.08) : DS.muted.opacity(0.06))
                    .overlay(
                        RoundedRectangle(cornerRadius: DS.rowRadius)
                            .stroke(isSelected ? DS.primary.opacity(0.40) : Color.clear, lineWidth: 1.5)
                    )
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - QuizProgressSection

/// 現在の問題番号・スコア・進捗ドットを1つにまとめたプログレス表示コンポーネント。
/// プレイ中画面の上部に固定表示される。
struct QuizProgressSection: View {
    var viewModel: EmojiQuizViewModel

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                // 「1 / 10」形式の問題番号テキスト。viewModel 側でフォーマット済みの文字列を返す
                Text(viewModel.progressText)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(DS.muted)
                Spacer()
                // 現在の正解数をゴールドの星アイコンとともに表示する
                HStack(spacing: 5) {
                    Image(systemName: "star.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(DS.gold)
                    Text("\(viewModel.score)")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(DS.textBody)
                }
            }
            // 問題数ぶんのドットを横並びで表示する進捗インジケーター
            FlexibleDots(
                count:        viewModel.questions.count,
                currentIndex: viewModel.currentIndex,
                results:      viewModel.results
            )
        }
    }
}

// MARK: - FlexibleDots

/// 問題数に応じて自動的に折り返すドット型進捗インジケーター。
/// 画面幅を GeometryReader で取得し、収まる列数を計算して複数行に折り返す
/// （GeometryReader の解説は ConfettiView.swift を参照）。
/// ファイル外から参照しないため private で隠蔽している。
private struct FlexibleDots: View {
    let count:        Int  // 総問題数
    let currentIndex: Int  // 現在表示中の問題インデックス（0始まり）
    let results:      [Bool]  // 各問題の正誤結果（回答済み問題のみ格納される）

    var body: some View {
        GeometryReader { geo in
            // ⚠️ 変更注意: dotSize / spacing を変えるときは、下の .frame(height:) 内に
            //   生数字で書かれている 8 / 5 も同じ値に揃えること（ずれると行が見切れる）。
            let dotSize: CGFloat = 8
            let spacing: CGFloat = 5
            // 画面幅からドットが何列収まるかを計算する
            let cols = max(1, Int((geo.size.width + spacing) / (dotSize + spacing)))
            // 総問題数と列数から必要な行数を算出する
            let rows = max(1, Int(ceil(Double(count) / Double(cols))))
            VStack(spacing: spacing) {
                ForEach(0..<rows, id: \.self) { row in
                    HStack(spacing: spacing) {
                        ForEach(0..<cols, id: \.self) { col in
                            let i = row * cols + col
                            if i < count {
                                // 問題インデックスに対応するドットを色付きで表示する
                                Circle()
                                    .fill(dotColor(index: i))
                                    .frame(width: dotSize, height: dotSize)
                                    .animation(.easeInOut(duration: 0.2), value: currentIndex)
                            } else {
                                // グリッドの余白セルを透明な Circle で埋め、レイアウトを揃える
                                Circle()
                                    .fill(Color.clear)
                                    .frame(width: dotSize, height: dotSize)
                            }
                        }
                    }
                }
            }
        }
        // 行数に基づいてフレームの高さを固定し、GeometryReader が無限に広がるのを防ぐ。
        // {...}() は「その場でクロージャを定義して即実行する」書き方で、
        // 複数行の計算結果を1つの引数として渡したいときに使う。
        // ⚠️ 変更注意: ここの 8 / 5 は上の dotSize / spacing と同じ値にすること。
        //   「20」は標準的な画面幅で1行に収まる列数の想定値（高さの見積もり専用で、
        //   実際の折り返し列数は body 内の cols が画面幅から計算する）。
        .frame(height: {
            let rows = max(1, Int(ceil(Double(count) / Double(20))))
            return CGFloat(rows) * 8 + CGFloat(max(0, rows - 1)) * 5
        }())
    }

    /// ドットのインデックスに応じた色を返す。
    /// 回答済み：正解→緑、不正解→赤 ／ 現在：プライマリ ／ 未回答：グレー
    private func dotColor(index: Int) -> Color {
        if index < currentIndex { return results[index] ? DS.gaugeFull : DS.gaugeWarn }
        if index == currentIndex { return DS.primary }
        return DS.muted.opacity(0.25)
    }
}

// MARK: - QuizQuestionCard

/// 現在の問題を表示するカード。モード（絵文字→テキスト or テキスト→絵文字）に応じて
/// 表示するコンテンツを切り替える。displayStyle によってフォントや背景も変わる。
struct QuizQuestionCard: View {
    let question:     QuizQuestion
    let mode:         QuizMode
    let displayStyle: DisplayStyle

    var body: some View {
        VStack(spacing: 10) {
            switch mode {
            case .emojiToText:
                // 絵文字→テキストモード：正解の絵文字（またはコード）を大きく表示する
                primaryDisplay(question.correct.emoji)
                Text(mode.questionLabel(for: displayStyle))
                    .font(.system(size: 26, weight: .medium, design: .rounded))
                    .foregroundStyle(DS.muted)
            case .textToEmoji:
                // テキスト→絵文字モード：正解の名前テキストを表示し、絵文字を当てさせる
                Text(question.correct.name)
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .minimumScaleFactor(0.4)  // 長い名前でもカードからはみ出さないよう縮小する
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 8)
                    .foregroundStyle(DS.textPrimary)
                Text(mode.questionLabel(for: displayStyle))
                    .font(.system(size: 26, weight: .medium, design: .rounded))
                    .foregroundStyle(DS.muted)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 180)  // カード高さを固定して問題切り替え時にレイアウトが跳ねるのを防ぐ
        .background(
            RoundedRectangle(cornerRadius: DS.cardRadius)
                .fill(DS.card)
                .shadow(color: .black.opacity(0.07), radius: 14, x: 0, y: 5)
        )
    }

    /// displayStyle に応じて問題の主表示（絵文字 / コード / テキスト）を切り替えるヘルパー。
    /// 3つのスタイルそれぞれでフォント・色・背景が異なるため @ViewBuilder で分岐する。
    @ViewBuilder
    private func primaryDisplay(_ text: String) -> some View {
        switch displayStyle {
        case .emoji:
            // 通常の絵文字カテゴリ：96ptの大きな絵文字をそのまま表示する
            Text(text).font(.system(size: 96))
        case .code:
            // コードカテゴリ（国旗コードなど）：等幅フォントでコードブロック風に表示する
            Text(text)
                .font(.system(size: 46, weight: .black, design: .monospaced))
                .foregroundStyle(DS.primary)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: DS.inputRadius)
                        .fill(DS.primary.opacity(0.08))
                )
        case .text:
            // テキストカテゴリ：文字列を大きく表示。長い文字列でも縮小して収める
            Text(text)
                .font(.system(size: 80, weight: .black, design: .rounded))
                .foregroundStyle(DS.primary)
                .minimumScaleFactor(0.5)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 16)
        }
    }
}

// MARK: - QuizChoiceGrid

/// 選択肢を2列のグリッドで表示するコンポーネント。
/// answerState を受け取り、回答後は各ボタンの状態（正解・不正解・薄表示）を切り替える
/// （LazyVGrid の解説は TitleView.swift を参照）。
struct QuizChoiceGrid: View {
    let question:    QuizQuestion
    let mode:        QuizMode
    let displayStyle: DisplayStyle
    let answerState: AnswerState
    let selectedItem: QuizItem?
    let onSelect:    (QuizItem) -> Void

    /// 2列固定のグリッド定義。static にして全インスタンスで共有する。
    private static let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    var body: some View {
        LazyVGrid(columns: Self.columns, spacing: 12) {
            ForEach(question.choices) { item in
                QuizChoiceButton(
                    item: item, mode: mode, displayStyle: displayStyle,
                    state: buttonState(for: item)
                ) { onSelect(item) }
            }
        }
    }

    /// 各選択肢ボタンの表示状態を決定するロジック。
    /// 未回答はすべて normal、回答後は正解・選んだ不正解・その他（dimmed）の3種に分類する。
    private func buttonState(for item: QuizItem) -> QuizChoiceButtonState {
        guard answerState != .unanswered else { return .normal }
        if item.id == question.correct.id { return .correct }
        if item.id == selectedItem?.id    { return .wrong }
        return .dimmed
    }
}

// MARK: - QuizChoiceButtonState

/// 選択肢ボタンの表示状態を表す列挙型。
/// normal：回答前 / correct：正解 / wrong：不正解で選択 / dimmed：回答後の非選択肢
enum QuizChoiceButtonState { case normal, correct, wrong, dimmed }

// MARK: - QuizChoiceButton

/// 選択肢1件を表示するボタン。state に応じて背景色・枠線・アイコンを切り替える。
/// 回答済み（state != .normal）のときは .disabled で再タップを防ぐ。
struct QuizChoiceButton: View {
    let item:        QuizItem
    let mode:        QuizMode
    let displayStyle: DisplayStyle
    let state:       QuizChoiceButtonState
    let action:      () -> Void

    /// state に応じた背景色を返す。正解は薄緑、不正解は薄赤、dimmed はさらに薄く。
    private var bgColor: Color {
        switch state {
        case .normal:  return DS.choiceFill
        case .correct: return DS.gaugeFull.opacity(0.15)
        case .wrong:   return DS.gaugeWarn.opacity(0.15)
        case .dimmed:  return DS.choiceFill.opacity(0.50)
        }
    }

    /// state に応じた枠線色を返す。正解・不正解のみ枠線を表示し、その他は透明または薄い枠。
    private var borderColor: Color {
        switch state {
        case .normal:  return DS.muted.opacity(0.15)
        case .correct: return DS.gaugeFull
        case .wrong:   return DS.gaugeWarn
        case .dimmed:  return Color.clear
        }
    }

    var body: some View {
        Button(action: action) {
            ZStack {
                RoundedRectangle(cornerRadius: DS.btnRadius)
                    .fill(bgColor)
                    .overlay(
                        RoundedRectangle(cornerRadius: DS.btnRadius)
                            .stroke(borderColor, lineWidth: 1.8)
                    )
                    // 回答前のみドロップシャドウを付けてタップ可能感を演出する
                    .shadow(color: .black.opacity(state == .normal ? 0.06 : 0), radius: 5, x: 0, y: 2)
                choiceContent
                // 正解ボタンの右上にチェックマークアイコンを重ねて表示する
                if state == .correct {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(DS.gaugeFull)
                        .font(.system(size: 18, weight: .bold))
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                        .padding(8)
                }
                // 不正解で選択したボタンの右上にバツマークアイコンを重ねて表示する
                if state == .wrong {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(DS.gaugeWarn)
                        .font(.system(size: 18, weight: .bold))
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                        .padding(8)
                }
            }
            .frame(height: 76)
        }
        .buttonStyle(.plain)
        .disabled(state != .normal)  // 回答後は再タップを無効化する
        // 正解ボタンのみわずかに拡大して正解を視覚的に強調する（MAKE10 の TileButton と同じ 1.03）
        .scaleEffect(state == .correct ? 1.03 : 1.0)   // ← 変更可
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: state)
    }

    /// mode と displayStyle の組み合わせに応じて選択肢の内容表示を切り替える。
    /// emojiToText モード：テキスト名を表示 / textToEmoji モード：絵文字・コード・テキストを表示。
    @ViewBuilder
    private var choiceContent: some View {
        switch mode {
        case .emojiToText:
            // 絵文字→テキストモード：選択肢はテキスト名で表示する
            Text(item.name)
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .minimumScaleFactor(0.5)
                .multilineTextAlignment(.center)
                .foregroundStyle(state == .dimmed ? DS.muted : DS.textPrimary)
                .padding(10)
        case .textToEmoji:
            // テキスト→絵文字モード：displayStyle に応じてさらに3通りに分岐する
            switch displayStyle {
            case .emoji:
                // 通常の絵文字で選択肢を表示する
                Text(item.emoji)
                    .font(.system(size: 50))
                    .opacity(state == .dimmed ? 0.40 : 1.0)
                    .padding(8)
            case .code:
                // コードカテゴリ：等幅フォントでコード文字列を表示する
                Text(item.emoji)
                    .font(.system(size: 20, weight: .black, design: .monospaced))
                    .foregroundStyle(state == .dimmed ? DS.muted : DS.primary)
                    .padding(10)
            case .text:
                // テキストカテゴリ：大きめのテキストとして選択肢を表示する
                Text(item.emoji)
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .minimumScaleFactor(0.5)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(state == .dimmed ? DS.muted : DS.textPrimary)
                    .padding(10)
            }
        }
    }
}

// MARK: - QuizFeedbackLabel

/// 回答後に正解・不正解を伝えるフィードバックラベル。
/// answerState に応じて何も表示しない／正解メッセージ／不正解＋正解表示の3パターンに分岐する。
struct QuizFeedbackLabel: View {
    let answerState:  AnswerState
    let correct:      QuizItem
    let mode:         QuizMode
    let displayStyle: DisplayStyle

    /// モードに応じて正解の表示形式を決める。emojiToText なら名前、textToEmoji なら絵文字を表示する。
    private var correctDisplay: String { mode == .emojiToText ? correct.name : correct.emoji }

    var body: some View {
        switch answerState {
        case .unanswered:
            // 未回答時は空文字で高さだけ確保し、レイアウトのガタつきを防ぐ
            Text("").font(.system(size: 26, design: .rounded))
        case .correct:
            // 正解時：丸アイコン＋正解ラベルを緑で表示する
            Label("quiz_feedback_correct", systemImage: "circle")
                .font(.system(size: 26, weight: .bold, design: .rounded))
                .foregroundStyle(DS.gaugeFull)
        case .wrong:
            // 不正解時：バツアイコン＋不正解ラベルと、正解を赤で表示する
            VStack(spacing: 4) {
                Label("quiz_feedback_incorrect", systemImage: "xmark")
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .foregroundStyle(DS.gaugeWarn)
                // 「こたえは〇〇だよ」形式で正解を表示する
                Text(String(format: String(localized: "quiz_feedback_answer_is"), correctDisplay))
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                    .foregroundStyle(DS.gaugeWarn)
                    .multilineTextAlignment(.center)
            }
        }
    }
}
