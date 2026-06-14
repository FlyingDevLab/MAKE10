# MAKE10 コメント規約 (Comment Style Guide)

> **To English-speaking visitors:** Sorry! All in-code comments in this repository are
> written in Japanese, as they are designed as learning material for Japanese-speaking
> beginners. We hope the code itself still reads well — thank you for stopping by. 🙇

このリポジトリのソースコードは、**Swift / SwiftUI の初学者がそのまま教材として読める**ことを目指してコメントを書いています。このドキュメントは、そのコメントがどんなルールで書かれているかをまとめたものです。

- **コードを読みに来た方へ** — このページは「読み方の案内図」として使えます。特に [§5 ★解説ブロック★](#5-解説ブロック-の使いどころ) と [§9 解説の所在マップ](#9-解説の所在マップ) を見ると、どのファイルにどの概念の解説があるかわかります。
- **コードを書く人(将来の自分・コントリビュータ)へ** — 新しいコードはこの規約に沿ってコメントを書きます。[§8 チェックリスト](#8-チェックリスト) で確認できます。

なお、コメントは**日本語のみ**で書いています。英日併記は分量が倍増してかえって読みにくくなるためです。この規約は新しく発明したものではなく、リポジトリ内の優良例(`CoinDropScene.swift` / `GameViewModel.swift`)で実践されていたスタイルを全ファイルの標準として明文化したものです。

---

## 1. ファイルヘッダ(全ファイル必須)

各ファイルの冒頭では、Xcode標準ヘッダの直後に**このファイルが何者かを3層で説明**しています。初めて開いたファイルでも、コードを読み始める前に全体像がつかめるようにするためです。

```swift
//
//  CoinDropScene.swift
//  FDL-TenBlitz
//
//  Created by 空飛ぶ研究室(FlyingDevLab) on 2026/05/30.
//
//  ① 一言サマリ(1〜3行): このファイルは何をするものか
//  コインを落とし、掴んで動かし、同種コインを集めて合体させ、
//  最終的に 50¢×2 → $1 を作るスイカ系の物理パズルシーン。
//
//  ② 役割分担: 関連ファイルとの責務の境界線
//  役割分担:
//    - Scene : 物理シミュレーション・出現・ドラッグ・合体・溢れ判定
//    - VM    : スコア/残り秒数/次コイン/画面遷移(CoinDropViewModel)
//
//  ③ ★初学者向け解説★(必要なら): このファイルを読むのに必要な前提知識
//  ★ SpriteKit を初めて読む人へ ★
//    SpriteKit はゲーム用のフレームワークで、...
//
```

- ①は**必須**。②は1つの機能を複数ファイルで構成しているとき必須。③は §5 の基準で判断。
- `Created by` 行はXcodeが生成したものをそのまま残しています。

---

## 2. `// MARK:` セクション構成(全ファイル必須)

`// MARK:` はXcodeのジャンプバー(エディタ上部のパンくずリスト)に目次として表示される特別なコメントです。すべてのファイルで、ジャンプバーだけで全体構造が読めるようにしています。

### 標準形(ViewModel / Model)
```swift
// MARK: - <型名>           ← 型ごとに「- 付き」MARK(区切り線が入る)
    // MARK: 定数            ← 型の中は「- なし」MARK
    // MARK: 永続化(UserDefaults / ScoreBoard)
    // MARK: 状態(ゲーム中に変化するプロパティ)
    // MARK: 初期化
    // MARK: <処理のまとまりごと: ゲーム開始 / タイマー / 回答処理 ...>
```

### 標準形(View)
```swift
// MARK: - <View名>
    // MARK: 依存(VM・Store・環境値)
    // MARK: ローカル状態(@State)
    // MARK: body
    // MARK: サブビュー
    // MARK: ヘルパー
```

### ルール
- セクション名は**日本語**で、処理の流れ順に並べる(定義順 ≒ 読む順)。
- 1ファイルに型が複数あるときは、ファイル冒頭ヘッダに「このファイルの構成」一覧を書く(`GamePickerComponents.swift` が実例)。
- 絵文字はMARKに使わない。例外: 調整パラメータブロックの「⚙️」のみ可。

---

## 3. ⚙️ 調整パラメータブロック

ゲームの挙動を決める数値(制限時間・速度・サイズなど)は、コード中に直書きせず1箇所に集約し、ブロックの先頭で「ここだけ触ればOK」と明示しています。**コードを改造して遊んでみたい人は、まずこのブロックを探してください。**

```swift
// MARK: - ⚙️ 調整パラメータ(ここだけ触ればOK)
//
// ┌─────────────────────────────────────────────┐
// │  <機能名> の数値定数を一箇所に集約。          │
// │  挙動を変えたいときはここだけ編集する。        │
// └─────────────────────────────────────────────┘

enum CoinDropTuning {
    /// コインが落下を開始する高さ(フィールド上端からのオフセット)
    static let dropY: CGFloat = 40   // ← 変更可
}
```

- 各定数には `///` で**単位と意味**を書く(「秒」「pt」「0.0〜1.0」など)。
- View側にどうしても残る数値(フォントサイズ等)には `// ← 変更可` を付ける。

### `// ← 変更可` の付与基準
| 付ける | 付けない |
|---|---|
| 見た目・難易度・ゲームバランスに直結する値 | レイアウト計算の中間値 |
| 安全に変更できる値 | 変更すると他と整合が崩れる値 |

逆に「変更すると壊れる値」には `// ⚠️ 変更注意: <理由>` を付けています。改造するときはこのマークに気をつけてください。

---

## 4. `///` ドキュメントコメント

`///`(スラッシュ3つ)はSwiftのドキュメントコメントで、Xcode上でOption+クリックするとポップアップ表示されます。

**対象: すべての public / internal なプロパティ・メソッド・型。**
private でも「名前だけでは役割が読めないもの」には付けています。

```swift
/// 紙吹雪の自動非表示を管理するための世代番号。
/// startGame のたびにインクリメントし、前のゲームの asyncAfter が
/// 次のゲームの紙吹雪を誤って消さないようにするための仕組み。
private var confettiGeneration: Int = 0
```

- 1行目: **何のための値/処理か**(What)。
- 2行目以降: 必要なら**なぜそうしているか**(Why)。Whyこそ初学者に価値がある情報だと考えています。
- `- Parameter` / `- Returns` は複雑なメソッドに限って付ける。全部には付けない。

---

## 5. ★解説ブロック★ の使いどころ

このリポジトリ最大の特徴です。コード中に `★ <概念名>とは? ★` という形式で、その場で読める入門解説を埋め込んでいます。

```swift
/// ★ AnyCancellable とは？ ★
///   Combine フレームワークの型で、「購読のライフサイクル管理」を担います。
///   この変数が nil になる（= cancel() を呼ぶ）とタイマーが止まります。
private var timerCancellable: AnyCancellable?
```

### 解説を書く基準(いずれかに該当したら書く)
1. **Swift/SwiftUIの中級概念** — `@Observable`, `AnyCancellable`, `GeometryReader`,
   `PreferenceKey`, `Codable`, ジェネリクス など
2. **フレームワーク固有の前提** — SpriteKitの座標系、SKPhysicsBodyの仕組み など
3. **このプロジェクト固有のパターン** — 世代番号パターン、didMove二重呼び出しガード、
   UDKey経由の永続化 など

### 書かない基準
- `if` / `for` / Optional binding などの基礎文法(入門書に譲ります)
- 名前から自明なこと(「scoreはスコアです」のような同語反復)

### 重複の扱い
同じ概念の★解説★は**プロジェクト内で原則1箇所(代表ファイル)だけに書き**、他のファイルでは1行で参照しています。どこに何の解説があるかは [§9 解説の所在マップ](#9-解説の所在マップ) を見てください。

```swift
// @Observable の解説は AppSettings.swift 冒頭を参照
```

---

## 6. 行内コメント

- **Whyを書く。Whatはコードに語らせる。**
  - 悪い例: `score += 1  // スコアを1増やす`
  - 良い例: `score += 1  // 連続正解ボーナスは加算しない(子ども向けに公平さ優先)`
- 処理の節目には `// ── 見出し ──────` 形式の区切りコメントを使うことがあります
  (`CoinDropScene.swift` が実例)。

---

## 7. エラーログの書式(統一)

子ども向けアプリのため、エラーをUIに表示しない方針です。その代わり、`do-catch` で握りつぶす場合も必ず以下の書式でログに痕跡を残します。

```swift
print("⚠️ <型名>: <何に失敗したか>: \(error.localizedDescription)")
```

- ログに個人情報を含めない(そもそもこのアプリは個人情報を扱いませんが、原則として)。
- `#if DEBUG` で囲む運用は現状していません。

---

## 8. チェックリスト

新しいファイルを書くとき・既存ファイルを変更するときの確認項目です。

- [ ] ファイルヘッダに「一言サマリ」がある
- [ ] 関連ファイルがあれば「役割分担」がある
- [ ] MARK構成が標準形に沿っている(ジャンプバーで流れが読める)
- [ ] マジックナンバーが定数置き場に集約されている
- [ ] 調整してよい値に `// ← 変更可`、危険な値に `// ⚠️ 変更注意` がある
- [ ] プロパティ・メソッドに `///` がある(自明なものを除く)
- [ ] ★解説★が基準に沿って配置され、重複していない
- [ ] 同語反復コメントがない(Whyが書かれている)
- [ ] エラーログが §7 の書式

---

## 9. 解説の所在マップ

「★解説ブロック★」がどのファイルにあるかの索引です。コードで学びたい方は、興味のある概念のファイルから読み始めるのがおすすめです。

| 概念 | 代表ファイル |
|---|---|
| エントリーポイント / @main / WindowGroup | FDL_TenBlitzApp.swift |
| シングルトン / static let / didSet / private init() | AppSettings.swift |
| @Observable とは | AppSettings.swift |
| UserDefaultsの読み方の使い分け（bool vs object+??） | AppSettings.swift |
| システムサウンド / UIImpactFeedbackGenerator | SoundManager.swift |
| case のない enum（名前空間） | ScoreBoard.swift |
| @discardableResult とは | ScoreBoard.swift |
| デザイントークン / CGFloat / some View | DesignSystem.swift |
| ジェネリクス / @ViewBuilder / @State | SharedFrame.swift |
| アプリ全体の zIndex 階層表 | SharedFrame.swift |
| Canvas / GeometryReader | ConfettiView.swift |
| LocalizedStringKey / Codable・try? | GamePickerComponents.swift |
| タップとフリックの1ジェスチャ判定 | GamePickerComponents.swift |
| 新しいゲームの追加手順 | GamePickerComponents.swift |
| @Environment(\.dismiss) / String(localized:) | ConsentView.swift |
| 外部リンクを使わない設計の理由 | ConsentView.swift |
| @Binding / @Bindable | SettingsView.swift |
| LazyVGrid / 2列グリッドの座標 | TitleView.swift |
| UserDefaultsキー文字列の変更禁止ルール | MakeTenModels.swift |
| ⚙️ 調整パラメータブロック（private enum C） | GameViewModel.swift |
| AnyCancellable / 世代番号パターン | GameViewModel.swift |
| [weak self] / repeat-while / タイマーの基準時刻方式 | GameViewModel.swift |
| 関連値付き enum | MakeTenContentView.swift |
| onReceive / NotificationCenter | MakeTenContentView.swift |
| .animation(value:) に渡すための String 変換 | MakeTenContentView.swift |
| .id() によるトランジション発火 / .animation(value:) | PlayingView.swift |
| ButtonStyle / 自己完結型コンポーネント | PlayingView.swift |
| 見えない背景での座標取得 / 座標の比率保存 | FinishedView.swift |
| タプルでの switch | QuizData.swift |
| Equatable の == を自分で書く理由 | QuizData.swift |
| カスタムデコード（init(from:)） | QuizCategoryLoader.swift |
| assertionFailure とは | QuizCategoryLoader.swift |
| @MainActor とは | EmojiQuizViewModel.swift |
| Task（Swift Concurrency）/ キャンセル | EmojiQuizViewModel.swift |
| Circle.trim で円形ゲージ | EmojiQuizResultView.swift |
| @AppStorage / .task / 出現順ユニーク化 | EmojiQuizHomeView.swift |
| SpriteKit 入門(ノード/物理) | CoinDropScene.swift |
| didMove 二重呼び出しガード | PinballScene.swift |
| CaseIterable とは（CoinType） | CoinDropViewModel.swift |
| CADisplayLink / 60fpsループ | MazeGameModel.swift |
| NSObject継承の理由 / @objc / #selector | MazeGameModel.swift |
| 再帰的バックトラック法（迷路生成） | MazeGameModel.swift |
| 1セル=3×3タイルのグリッド設計（GW=MC*3+1） | MazeGameModel.swift |
| 円 vs 壁タイルの当たり判定（最近接点） | MazeGameModel.swift |
| トンネリング対策のサブステップ移動 | MazeGameModel.swift |
| TimelineView(.animation) / 60fps描画ループ | MazeGameView.swift |
| 論理座標 ⇄ ビュー座標のスケール変換 | MazeGameView.swift |
| GraphicsContext は値型（コピーして局所変形） | MazeGameView.swift |
| タイマーの毎tick加算による計時方式 | JankenViewModel.swift |
| 即時実行クロージャ {...}() で値を確定 | JankenViewModel.swift |

> このマップは、コメント整備の進行に合わせて随時更新します。
