# 審査メモ（App Review への説明）— v1.6.0

App Store Connect の「審査メモ」にそのまま貼る（4,000文字まで。下の英文は約3,300文字）。
今回はデータの扱いが変わった（iCloud に保存できるようになった）ので、その説明をいちばん上に置いている。

```text
Version 1.6.0 – Notes for Review

1. New app name
   The app is renamed "Kids Games by Flying Dev Lab" (localized names are used in each language). The content is the same game collection as before. "MAKE10" was the previous name and is the name of one of the games inside the app.

2. iCloud sync (change in data handling)
   Players can now save their progress to their own iCloud account, so they can continue on a new device.
   - Technology: CloudKit private database only (CKSyncEngine). No public or shared database is used.
   - Data saved: high scores, in-game Energy, stickers, sticker book pages (including drawings), the wallpaper drawing, and Thank-You Notebook checkmarks. No names, contact details, photos, location or device identifiers are saved.
   - The data is stored only in the user's own private iCloud database. The developer cannot access it, and it is not shared with any third party. There is no server operated by the developer.
   - Sync starts only after the parent agrees to the updated Privacy Policy on the first launch. Because the data handling changed, existing users are asked to review and agree to the Privacy Policy again after updating.
   - Sync can be turned off at any time in Settings (gear icon on the title screen > "Save to iCloud").
   - If the device is not signed in to iCloud, or is offline, the app works normally and keeps all data on the device.
   - Because the developer never receives or can access this data, our App Privacy answer remains "Data Not Collected."

   How to test: sign in to iCloud on the device, play a game (for example MAKE10), then open Settings to see the iCloud status. To see the data restored, install the app on a second device signed in to the same Apple Account.

3. Landscape, resizable windows and iPhone Duo
   The app now supports landscape on iPad and iPhone, Split View and Stage Manager window resizing on iPad, and the unfolded screen of iPhone Duo. Three games (Pinball, Coin Drop and Ten Puzzle) are designed for portrait; they rotate the screen to portrait when possible and are centered in wide windows.

4. Animal Match card sets
   The memory game now offers six card sets: Animals (4×5), Animals (5×5), Fruits, Star signs, Months (English) and Months (kanji). The star signs are presented only as their symbols, names and the figures they represent (for example, Aries and a ram), as general knowledge. There is no fortune-telling content.

5. Stickers and Energy
   The sticker book now has 12 pages and there are 273 stickers. Unused stickers can be exchanged back into Energy. Energy is an in-game point earned only by playing; it cannot be bought with real money and has no cash value. Every sticker in the Gacha has the same chance of appearing.

6. Bonuses
   Each game gives a small Energy bonus the first time it is finished each day. Users updating from a previous version receive a one-time gift of 10,000 kcal of Energy.

7. Other
   Improved translations in all 15 languages and minor fixes.

The app continues to contain no ads, no in-app purchases, no third-party SDKs, no analytics and no tracking. Apart from the optional iCloud sync described above, the app does not connect to the internet. The source code is publicly available at https://github.com/FlyingDevLab/MAKE10.

Thank you for your review.
```

## 指摘されたときのメモ

- **iCloud とプライバシーの回答**: 保存先は CloudKit のプライベートデータベース（利用者本人の iCloud）だけ。開発者は中身を見られず、受け取ってもいないので、Apple の定義では「収集」にあたらない（App のプライバシーは「データの収集なし」のまま）。同意の前は同期を始めない（CloudSyncManager.start）。設定でオフにでき、オフにすると端末の中だけに保存する。
- **CloudKit のスキーマ**: 審査の前に Production にデプロイしておくこと（していないと、審査の端末で同期できない）。
- **もう一度の同意**: 1.6.0 に更新すると同意の画面がもう一度出る（AppMigration.migrateTo160）。データの扱いが変わったため。
- **星座**: 占いの機能はなく、記号・名前・もとになった形（おひつじ座と 🐏 など）を覚えるカード。宗教の記号ではない。
- **旗**: アプリ内の呼び名は「はた（Flags）」「せかいの旗（World Flags）」。教育目的で、国連加盟国を基準に選んでいる（台湾・香港・ニューカレドニア・バチカン・パレスチナ・コソボも含む）。
- **ガチャ**: 全273種が同じ確率。エネルギーは遊んだときだけ増え、お金では買えない。シールをエネルギーに戻せるが、現金の価値はない。
- **アプリ名の「by Flying Dev Lab」**: 開発者名（App Store の販売元の表記と同じ）。
