# 空港コードクイズのデータを作り直す

`MAKE10/Resources/JSON/airport*.json` は、このフォルダのスクリプトで作っている。

## 使うデータ
- **OurAirports**（パブリックドメイン）: 空港の一覧。IATA コードがあり、閉鎖されておらず、定期便がある（`scheduled_service = yes`）空港だけを使う。
- **Wikidata**（CC0）: 空港名と都市名の日本語・英語・現地の言葉。

## 手順
作業用のフォルダ（例: `/tmp/airports`）を決めて、そこで行う。

```bash
mkdir -p /tmp/airports/wd
curl -L -o /tmp/airports/airports.csv https://davidmegginson.github.io/ourairports-data/airports.csv
python3 tools/airports/fetch.py /tmp/airports    # Wikidata から名前を取る（数分かかる）
python3 tools/airports/build.py /tmp/airports    # 空港ごとにまとめる
python3 tools/airports/emit.py /tmp/airports MAKE10/Resources/JSON   # JSON を書き出す
```

## 名前の決まり
- 名前は「日本語」「英語」「現地の言葉」の3つだけ持つ。ほかの言語の人には英語が出る（QuizCategoryLoader の英語フォールバック）。
- 国ごとのカテゴリは空港名だけ。「世界」だけ「空港名（都市名）」にする（空港名に都市名が入っているときは付けない）。
- 日本語名に英語が混ざっているもの（Wikidata のラベル）は使わず、英語名を出す。
- 日本の空港の日本語名は、`airportJapan.json` にいま入っている名前（愛称つき）を優先する。新しい空港が増えたときは、その空港の日本語名を確かめてから直す。
- オランダは、カリブ海の地域（アルバ・キュラソー・シント・マールテン・ボネール等）も入れて「オランダ王国」として数える。
