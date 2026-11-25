# SiriGemini15 0.1.0（段階0：骨組み）

iPhone 7（iOS 15 / Dopamine rootless）向け。
Siri に話した言葉を Google Gemini（無料枠）に送って、答えを読み上げる
tweak を作っていきます。これは最初の骨組みです。
光る Siri の見た目は、別の無料 tweak「LiquidSiri」が担当します。
この tweak は Siri の見た目には触らないので、ぶつかりません。

## この版（0.1.0）に入っている物

| 部品 | 中身 |
|---|---|
| 設定画面 | 全体スイッチ／Gemini APIキーの入力欄／モデル選択（ボタン2つ） |
| APIテスト | 「接続テストです。短く挨拶して」を Gemini に送り、返事を読み上げる＋止めるボタン |
| Siri出現ログ | Siri を出すと、ログに SIRI_UI_SEEN が残る（目撃だけ。横取りはまだ） |
| ログ | /var/mobile/Library/Logs/SiriGemini15.log に段階を記録 |
| 失敗ブレーキ | 例外が5回続いたら全活動を自動停止（リスプリングで解除） |
| 注入範囲 | SpringBoard だけ（骨組みでは広げない） |

## まだ入っていない物（次の段階で1つずつ）

| 段階 | 中身 |
|---|---|
| 1 | 言葉の横取り：Siri が認識した文字を取って Gemini に送る |
| 2 | Siri の声で返答＋会話の継続（前の話を覚える） |

## 準備（鳥さんがやること）

1. Google AI Studio で Gemini の APIキー を無料で取る（Googleアカウントだけ・カード不要）
2. この tweak を入れたあと、設定アプリ → SiriGemini15 → APIキーの欄に貼る

## 入れ方

1. Sileo で SiriGemini15_Dopamine_Rootless.deb をインストール
2. リスプリング
3. 設定アプリ → SiriGemini15

## 実機テスト（段階0）

| # | 確かめること | 合格の目印 |
|---|---|---|
| A | いつも通り使えるか | Safe Mode に入らない |
| B | 設定アプリに「SiriGemini15」が出るか | 一覧にある |
| C | 設定画面が開くか | スイッチと項目が見える |
| D | APIキーを貼って、閉じて開き直す | キーが残っている |
| E | モデルを「Flash」に変える | 「（今これ）」が Flash に移る |
| F | 「APIテスト」を押す | Gemini の挨拶が読み上げられる |
| G | Siri を出してみる | ログに SIRI_UI_SEEN が残る（Filza で確認） |
| H | LiquidSiri と両方入れた状態で Siri を出す | 見た目が LiquidSiri のまま、落ちない |

全部 OK だったら教えてください。次は段階1「言葉の横取り」を作ります。
どこかおかしかったら、どれがダメか教えてください（ログ SiriGemini15.log が手がかりになります）。
