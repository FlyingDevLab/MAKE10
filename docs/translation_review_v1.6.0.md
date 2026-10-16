# 翻訳チェック結果（v1.6.0・2026-10-16）

> 2026-10-16: A〜C はすべて修正済み（166か所）。D もすべて修正済み（225か所）。E は画面に出ないので、いまのままにする（ユーザー判断）。

対象: `Localizable.xcstrings` の 495キー × 15言語（ja / en / de / es / fr / hi / id / it / ko / nl / pt-BR / th / vi / zh-Hans / zh-Hant）

機械チェック（`%lld` などの差しこみ記号の数・種類、言語の抜け）は、すべて問題ありませんでした。
以下は、全文を読んで見つけた修正候補です。番号で「A1, A3 を直して」のように指示してください。

- 「→」の右が修正案です。
- 言語コード: de=ドイツ語, es=スペイン語, fr=フランス語, hi=ヒンディー語, id=インドネシア語, it=イタリア語, ko=韓国語, nl=オランダ語, pt-BR=ポルトガル語（ブラジル）, th=タイ語, vi=ベトナム語, zh-Hans=中国語（簡体字）, zh-Hant=中国語（繁体字）

---

## A. 明らかなまちがい（直すのをおすすめ）

**A1. シールじてんの「せいざ」カテゴリの名前がない（全言語）**
`sticker_category_zodiac` が翻訳ファイルにないため、じてんの見出しに「sticker_category_zodiac」という文字がそのまま出ます（今回のシール追加で私が入れ忘れたものです）。
→ ja せいざ / en Star Signs / de Sternzeichen / es Zodiaco / fr Zodiaque / hi राशियाँ / id Zodiak / it Zodiaco / ko 별자리 / nl Sterrenbeelden / pt-BR Zodíaco / th ราศี / vi Cung hoàng đạo / zh 星座

**A2. zh「没用的贴纸」が「役に立たないシール」の意味になっている（zh-Hans / zh-Hant）**
「つかっていない」の訳が「没用的（＝役に立たない）」になっています。3か所。
- `sticker_exchange_all_body` / `sticker_exchange_all_button` / `sticker_exchange_counts`
→ 「没用过的」（または「还没用的」）。zh-Hant は「沒用過的」

**A3. コインドロップの「NEXT」（次に落ちるコイン）が「次へ進む」の意味になっている**
`NEXT`: ja「つぎへ」/ de「WEITER」/ id「LANJUT」/ it「AVANTI」/ zh「下一步」は、いずれも「先へ進む」の意味です。
→ ja つぎ / de NÄCHSTE / id BERIKUTNYA / it PROSSIMA / zh 下一个（zh-Hant 下一個）/ fr「SUITE」→ SUIVANTE
同じく MAKE10 の `playing_next_label` も de「WEITER」→ NÄCHSTE

**A4. 四則テンパズルの大見出し（`四則演算テンパズル`）**
- nl「Rekenrätsel」は「rätsel」がドイツ語です → Rekenpuzzel
- de「Zehn-Puzzle」は「算数の」の意味が抜けています（ほかの言語は「算数パズル」）→ Rechenrätsel

**A5. 絵文字クイズの「よみかた」が nl で「講演」の意味になっている**
nl「lezing」は「講演・講義」の意味です。de「Lesen」も「読むこと（動作）」の意味です。
- 該当: `quiz_desc_char_to_reading` / `quiz_desc_emoji_to_text` / `quiz_desc_reading_to_char` / `quiz_desc_text_to_emoji` / `quiz_mode_*`（6か所）
→ nl uitspraak（発音）/ de Aussprache（発音）

**A6. hi「おとなの男の人・女の人」が「大きな男・大きな女」になっている**
`shop_tip_day_man`「एक बड़ा आदमी」/ `shop_tip_day_woman`「एक बड़ी औरत」
→ एक वयस्क पुरुष / एक वयस्क महिला

**A7. id もぐら叩きの説明で、もぐらが「ネズミ」になっている**
`Hit as many moles…`「tikus」はネズミです（タイトルは正しく「Tikus Tanah」）→ tikus tanah

**A8. de 迷路の説明の文法ミス**
`Drag to move the white mouse`「Weißen Maus durch Ziehen bewegen」→ Weiße Maus durch Ziehen bewegen

**A9. de シールやさんのひとこと（`shop_tip_game_energy`）で「ガチャをシールと交換する」と読める**
「…drehst du mit Energie (kcal) die Gacha und tauschst sie gegen Sticker.」の「sie」がガチャを指しています。
→ In diesem Spiel kannst du mit Energie (kcal) die Gacha drehen oder Sticker eintauschen.

**A10. en お絵かき全消去の確認の英文がおかしい**
`drawing_clear_alert_title`「Clear All Drawing?」→ Clear the whole drawing?

**A11. es クイズ満点の「¡」と「!!」の数が合っていない**
`quiz_result_perfect`「¡Perfecto! ¡Increíble!!」→ ¡Perfecto! ¡¡Increíble!!

**A12. es / pt-BR テンパズル「自力で正解」の文法**
es「Resueltos por ti solo」→ Resueltos por tu cuenta / pt-BR「Acertos sozinho」→ Acertos sem ajuda

**A13. hi テンパズルの入力欄の案内が途中で切れている**
`数字タイルをタップして式を作ろう`「अंक टाइल्स टैप करें」（「式を作ろう」が抜けている）→ अंक टाइल्स टैप करके समीकरण बनाओ

**A14. id / th ありがとう てちょうのカレンダーで「この日」が「きょう」になっている**
`thanks_calendar_empty` id「…hari ini」/ th「วันนี้…」はどちらも「きょう」→ id Tidak ada catatan di hari itu / th วันนั้นไม่มีบันทึก

**A15. de iCloud の「そろえています…」が命令のように読める**
`icloud_status_syncing`「Mit iCloud synchronisieren …」→ Wird mit iCloud synchronisiert …

**A16. de 指令じゃんけんの名前が文法的に不自然**
`janken_title`「Befehl Stein-Schere-Papier」（「命令 じゃんけん」と単語を並べただけ）→ Kommando-Schere-Stein-Papier
（`update_gift_janken_note` の中の名前も同じく直します）

**A17. fr 迷路の「チャージちゅう…」が「読み込み中」の意味**
`maze_hud_charging`「Chargement…」→ Recharge…

---

## B. 意味は通じるが不自然・もっと良い言い方がある

**B1.** じゃんけんの `%lld手`: en「hands」→ rounds / zh「%lld手」→ %lld局
**B2.** hi 迷路の「チーズ」が「पनीर（インドのカッテージチーズ）」→ चीज़（`Cheese Collected` / `Collect all 3 cheeses…`）
**B3.** hi `Back to Title`「शीर्षक पर वापस（見出しへ戻る）」→ मुख्य स्क्रीन पर वापस
**B4.** hi 「さいしょから はじめる」「शुरू से शुरू करें（はじめから はじめる、のくり返し）」→ नए सिरे से शुरू करें（`reset_confirm_progress_title` / `settings_reset_progress`）
**B5.** hi `energy_reward_clear_bonus`「क्लियर इनाम（英語の clear をそのまま）」→ पूरा करने का इनाम
**B6.** zh クイズ不正解「遗憾…（かたい言い方）」→ 可惜…（zh-Hant 可惜…）
**B7.** nl ありがとう てちょうの「いままで」「Altijd（いつも）」→ Sinds het begin
**B8.** nl 結果画面の「あそんだぶん」「Spel（ゲーム）」→ Gespeeld
**B9.** nl 「あそびかた」「Hoe te spelen（英語の直訳）」→ Zo speel je（`How to Play` / `janken_how_to_play_title`）
**B10.** de 「さいこうきろく」「Bester Rekord（不自然）」→ Rekord / de スコアの「Ergebnis（結果）」→ Punkte（`Score` / `Your Score`）
**B11.** it テンパズルのヒント「Aiuto（＝助けて）」→ Suggerimento（関連: Aiuti usati → Suggerimenti usati など5か所）
**B12.** 自動交換のボタン: es「Cambiar sola」/ pt-BR「Trocar sozinho」（「ひとりで交換」）→ Cambiar automáticamente / Trocar automaticamente。fr「Échanger auto」（くだけた略し方）→ Échange automatique。fr `sticker_auto_toggle`「si elle sort」→ s'il sort（シールは男性名詞）
**B13.** どうぶつめくりの「せいざ」ボタン: es「Signos」/ fr「Signes」/ it「Segni」/ pt-BR「Signos」は「記号・しるし」とも読める → es Zodiaco / fr Zodiaque / it Zodiaco / pt-BR Zodíaco
**B14.** pt-BR ピンボール `pinball_howto_lives`「você perde uma vez. 3 vezes!」→ você perde uma chance. 3 chances!
**B15.** ko `quiz_result_nice_try`「잘 노력했어!（不自然）」→ 열심히 했어! / ko 色の「하늘」→ 하늘색
**B16.** de もぐら叩き `Tap fast when they pop up!` カンマ抜け → Schnell tippen, wenn sie aus dem Loch kommen!
**B17.** de じゃんけんの「かって！」「SIEGEN!（勝利する、の硬い言い方）」→ GEWINNEN!（`janken_instruction_win` と `janken_how_to_play_body`）
**B18.** en / fr クイズの問題数「%lld Q」→ en %lld questions / fr %lld questions（`quiz_category_item_count`。幅が足りるかは画面で確認）
**B19.** zh-Hans で「」を使っている（簡体字では “ ” が一般的）→「凑不出！」を “凑不出！” に（2か所）
**B20.** zh `shop_tip_2000_bananas` だけ kcal が「千卡 / 大卡」になっている（ほかのひとことは kcal）→ 2000kcal
**B21.** es `praise_score_0`「¡La próxima vez!（次回！だけ）」→ ¡La próxima vez lo logras!
**B22.** th / hi `Play Again`「ลองอีกครั้ง / फिर कोशिश करें（もう一度ためす）」→ เล่นอีกครั้ง / फिर से खेलें（ほかの「もういちど」とそろえる）
**B23.** nl コインの説明「smelten（溶ける）」→ samensmelten（合体する）
**B24.** ko `gacha_new`「NEW」が英語のまま → 새로（または 신규）。韓国のアプリでは英語の NEW もよく使うので、そのままでも可

---

## C. 用語・表記のゆれ（そろえるのをおすすめ）

**C1.** fr シールの言葉が「sticker」（23か所）と「autocollant」（5か所）でまざっている → sticker にそろえる
**C2.** th シールのつづりが「สติกเกอร์」（28か所）と「สติ๊กเกอร์」（3か所）でまざっている → สติกเกอร์（正式なつづり）にそろえる
**C3.** hi ガチャのつづりが「गाचा」（4か所）と「गचा」（2か所）→ गाचा にそろえる
**C4.** ko ガチャが「뽑기」（7か所）と「가챠」（1か所: `shop_tip_game_energy`）→ 뽑기 にそろえる
**C5.** de / es / fr / it / pt-BR ガチャの性（男性・女性）がばらばら（`shop_tip_game_energy` だけ女性扱い）→ ほかの2か所に合わせて男性扱いにそろえる
**C6.** せっていの画面名と、文中の「せっていで…」の言葉がちがう
- fr タイトル「Paramètres」・文中「réglages」→ タイトルを Réglages に（iPhone の fr 表記もこちら）
- pt-BR タイトル「Configurações」・文中「Ajustes」→ タイトルを Ajustes に
**C7.** 「あそびかた」が2つのキーで訳がちがう（`How to Play` と `janken_how_to_play_title`）
- de「Spielanleitung」/「Wie man spielt」、ko「플레이 방법」/「게임 방법」、zh「怎么玩」/「玩法说明」→ それぞれ前者にそろえる
**C8.** 「ゲームスタート」が2つのキーで訳がちがう（`Start Game` と `ゲームスタート`）
- en「Start Game」/「Game Start」、fr「Démarrer」/「Démarrer le jeu」、vi「Bắt đầu」/「Bắt đầu trò chơi」→ 前者にそろえる
**C9.** ja `make10_title`「１０をつくろう」だけ全角の「１０」（同意画面などは半角の「10」）→ 10をつくろう
**C10.** ja チャレンジの表示「交互」（`janken_phase_alternate_short`）と、切りかえの文字「つぎは こうご！」で表記がちがう → こうご
**C11.** ko 「もどる」が「뒤로」と「돌아가기」でちがう → 뒤로 にそろえる
**C12.** de 「秒」の略が「Sek」と「Sek.」でまざっている → Sek.（`+5秒` / `janken_how_to_play_penalty` / `title_mode_*_label`）
**C13.** vi 子どもへの呼びかけが「bạn」（ほとんど）・「con」（どうぶつめくり）・「em」（かべがみ）・「tôi」（もっているシール）でまざっている → bạn / mình にそろえる
**C14.** vi 「どうぶつ」が「Con vật」（どうぶつめくり）と「Động vật」（じてん）→ Con vật にそろえる
**C15.** de / es / fr / it / nl / pt-BR 自動交換の文だけ、ガチャを「機械（Automat / máquina / machine…）」と言っている → Gacha にそろえる
**C16.** de / it ピンボールのタイトル「Pinball」→ どちらの国でも「Flipper」が一般的（任意）

---

## D. 方針を決めてほしいもの

**D1. 日本語の漢字（子ども向けの画面）**
アプリ全体はひらがな中心ですが、つぎの画面は漢字のままです。ひらがなにそろえますか？
- 迷路の説明（「3コーナーのチーズを全部集めたら次のステージ！」「赤いネズミと青いネズミは、壁に沿って迷路をまわる！」「衝撃波」など8か所）
- お絵かき（「絵を全部消しますか？」「この操作は元に戻せません。」「全消去」「消しゴム」「消す」）
- じゃんけん（「指令が出るよ！」「指令じゃんけん」「交互」）・「もぐら叩き」・迷路「🧀 全部ゲット！」
- 星座の名前「おひつじ座」など（どうぶつめくりの結果画面に出るようになったので、子どもが目にします）→ おひつじざ など
- テンパズル（大人向け）・同意画面・ポリシー（保護者向け）は、いまの漢字のままでよいと考えます

**D2. 保護者向けの文の敬語**
日本語は同意画面・iCloud の2択・リセットの確認でていねい語ですが、de / fr / it / es / nl / pt-BR は子ども向けと同じ「du / tu」です。
- 保護者向けだけ「Sie / vous / usted …」にしますか？（fr は お問い合わせ だけ「Veuillez（vous）」でまざっています）
- hi `reset_confirm_progress_body` は1つの文の中で「तुम्हारा（くだけた）」と「आप（ていねい）」がまざっています → どちらかにそろえる
- ko は子ども向けの文で「〜해!（タメ口）」と「〜해요（です・ます）」がまざっています（例: もぐら叩き「잡아!」「탭해!」、正解「이야」）→ 해요体にそろえますか？

**D3. 男の子・女の子どちらにも合う言い方**
es / fr / it / pt-BR などで、男性形だけになっている文があります。性別によらない言い方に変えますか？
- 「本当にいい？」es ¿Estás seguro? / fr Es-tu sûr ? / it Sei sicuro?（リセット確認）
- 「きてくれて ありがとう」fr Merci d'être venu ! / it Grazie di essere passato!（ログインボーナス）
- 「さいこう」de Der Beste / es El mejor / fr Le meilleur / it Il migliore / nl De beste / pt-BR O melhor（スコア 50〜99）
- 「じぶんで きがえ」es Vístete solo / fr tout seul / it da solo / pt-BR sozinho、「じぶんに ありがとう」es a ti mismo など
- ありがとう てちょうの「ともだち」「せんせい」が男性形（de Freund / Lehrer、es Amigo / Maestro、fr Ami / Maître、it Amico / Maestro、nl Vriend / Leraar、pt-BR Amigo / Professor）
  ※ de Freund・nl Vriend は「彼氏」の意味にもなります

**D4. 「じゃんけん」の呼び方**
ko / zh / vi はその国の呼び方（가위바위보 / 剪刀石头布 / Oẳn tù tì）ですが、es / fr / it / pt-BR / id / nl / hi / th は「Janken」のままです。
その国の子どもが知っている言葉にしますか？
- 案: es Piedra, papel o tijera / fr Pierre-feuille-ciseaux / it Carta, forbice, sasso / pt-BR Pedra, papel e tesoura / id Suit / nl Steen-papier-schaar / hi पत्थर-कागज़-कैंची / th เป่ายิ้งฉุบ

**D5. スコア1000以上の「神レベル」**
en「God Level」、hi「भगवान स्तर（神さまレベル）」などは、国によっては宗教的に気になる人がいるかもしれません。
「伝説レベル」（en Legendary / hi महान स्तर など）に変えますか？（日本語はそのまま）

**D6. 「おばあちゃん・おじいちゃん」**
th「คุณย่า / คุณปู่」、hi「दादीजी / दादाजी」、zh「奶奶 / 爷爷」は、どれも「父方の」祖父母だけを指します。
両方をふくむ言い方（th ย่า・ยาย / hi दादी-नानी など）にしますか？

**D7. コインドロップのタイトル**
ほかのゲームの名前は訳していますが、コインドロップだけ全言語で「CoinDrop」（英語）のままです。ゲームの名前としてこのままでよいですか？

---

## E. 管理まわり（画面には出ない）

**E1.** 34キーが「確認待ち（needs_review）」の状態です（テンパズルの文字、お絵かきの色、じゃんけんの切りかえなど）。
訳は入っていて画面にも出ますが、Xcode で黄色の印が付きます。今回の確認が済んだら「確認済み」にします。

**E2.** 使われていないキーが8つあります（「+」「10」「✨」「BLAST %@」「Charging…」「HI 🧀×%lld」「game_picker_sticker」「sticker_storage_hint_up」）。
→ 削除しても画面は変わりません。

**E3.** 翻訳者向けの説明（コメント）が古いものがあります。
- 星座・動物の名前の説明が「画面には出さない」のまま（星座はどうぶつめくりの結果画面に出るようになった）
- `難問 + 作れない問題が混在…` の説明が別の内容（「1回あたりの出題数」）になっている

---

## 参考: 確認したが問題なかったもの

- プライバシーポリシー全文: 15言語とも、見出しの数・順番・日付（2026年10月15日）・iCloud の説明の数がそろっています（10月15日にご確認済みの内容）
- 差しこみ記号（%lld / %@ / %1$lld など）: 全言語で数・種類が一致
- 動物・果物・星座・色の名前、ありがとう てちょうのミッション、シールやさんのひとこと、カテゴリ名: A〜D に挙げたもの以外は自然な訳です
