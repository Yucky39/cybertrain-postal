# cybertrain-postal 設計メモ(初版・ドラフト)

調査元は saeki-mototsune/CyberTrain(Spinel 2026.09.12 向け、v0.2.1、pre-alpha)の README、docs/design.md、spikes/NOTES.md、cybertrain/crypto.rb などである。
認証ライブラリ(改札)は別リポジトリで扱い、本書はポスタル(SMTP)に関する部分だけを載せる。

## 1. 前提(CyberTrain 側の事実)

- 言語は Ruby。アプリは CRuby では動かさず、Spinel で単一ネイティブバイナリにコンパイルする。実行時に gem は使えない。
- ライブラリは spin パッケージ(spin.toml の `[package]`)として配布する。
- メタプログラミング(`send` / `instance_exec` / `method_missing` / `define_method` / `eval`)は使わない。
- テストは `test/<name>.rb` と `test/<name>.rb.expected`(スナップショット)で、`spin test` が比較する。minitest / RSpec は使えない。`require "cybertrain/test"` が必須である。
- CyberTrain 本体は TLS を逆プロキシに任せており、`openssl` パッケージは使っていない。HMAC は `Digest::SHA256` の上に Ruby で実装している。
- Spinel の README にソケットクラスと TLS の記載はない。FFI と、パッケージが `.c` を持てることは明記されている。

## 2. 方針

- 名前空間は `Cybertrain::Postal`。ファイルは `cybertrain/postal.rb` と `cybertrain/postal/*.rb` に置く。
- CyberTrain 本体には依存させない。依存方向は CI のスクリプトで確認する(本体の `script/check-http-layer` に倣う)。
- spikes/NOTES.md の規則 1〜59 を制約として扱う。特に効くもの:
  - 規則 1・2: 非リテラルの `send` と、保存したブロックの `instance_exec` は使わない。
  - 規則 3・10・34: 基底クラスに抽象スタブを置く。同名メソッドは戻り値の型も揃える。
  - 規則 13: 文字列バッファは `+""` で作る。
  - 規則 20: ソケットの `readpartial` の直前に必ず `wait_readable(timeout)` を置く。
  - 規則 21: ソケットを `Thread.new` の引数に渡さず、メソッド経由で生成する。
  - 規則 27: ネットワークのバッファは `byteindex` / `byteslice` / `bytesize` で扱う。
  - 規則 40・42: 独自メソッドに `call` を使わない。lambda をキーワード引数で渡さない。
  - 規則 47・53・54: 例外は階層で見分けられない。`rescue` 句の列挙とクラス名で見分ける。
  - 規則 58: `Foo.new(その場で作った文字列)` は避け、ローカル変数に束縛してから渡す。
- 全体を require する統合テストを 1 本置く(規則 36・41)。

## 3. 責務

- 責務: メッセージの組み立て(RFC 5322 / MIME)、SMTP クライアント(RFC 5321 / 6152 / 3207 / 4954)、配送の抽象化、テスト用・開発用の配送先。
- 非責務: 受信、キューの永続化(M3 以降で検討)、テンプレート描画(CyberTrain のテンプレートエンジンとは連携層で結ぶ)。

## 4. 構成案

| 層 | 主なクラス | 役割 |
| --- | --- | --- |
| メッセージ | `Message`, `Address`, `Header`, `Mime` | 宛先・件名・本文・添付。ヘッダ値の CR/LF は拒否する(ヘッダインジェクション対策)。日本語の件名・表示名は RFC 2047 でエンコードする。本文は UTF-8 の base64 または quoted-printable。 |
| プロトコル | `Reply`, `ReplyParser`, `Session` | 複数行応答の解析、EHLO → STARTTLS → EHLO → AUTH → MAIL FROM → RCPT TO → DATA → QUIT の状態遷移。DATA のドットスタッフィングと行長制限(998 バイト)を守る。 |
| トランスポート | `PlainTransport`, `TlsTransport`, `ScriptedTransport` | 入出力の抽象。`ScriptedTransport` は応答を台本で返し、送った内容を記録する(テスト用)。 |
| 配送 | `SmtpDelivery`, `LogDelivery`, `TestDelivery` | `deliver(message)` の窓口。開発環境はログ出力、テストは記録のみ。 |

- 認証は PLAIN と LOGIN から始める。XOAUTH2 は M3 以降で検討する。
- 結果は例外ではなく `Result`(成功可否、SMTP コード、拡張ステータス、一時失敗か恒久失敗か)で返す `deliver` と、失敗時に例外を投げる `deliver!` の 2 本立てにする。例外が階層で判別できないため、リトライ判定は 4xx / 5xx のコードで行う。
- 例外クラスは接続失敗・タイムアウト・プロトコル違反・認証失敗を別クラスにし、`rescue` の列挙で分ける。

## 5. セキュリティの既定値

- STARTTLS が提供されているのに失敗した場合は、平文へ降格せず送信を中止する(ストリッピング対策)。
- 認証情報は、暗号化されていない接続では送らない。ただしループバックと Unix ソケットは例外とする。
- 平文接続を許可するには `allow_insecure: true` を明示させる。
- 宛先・本文・認証情報はログに出さない。
- 接続・応答・全体の各待機にタイムアウトを持たせる。

## 6. 最大の技術リスク: TLS

Spinel の TLS サポートは現時点で未確認である。選択肢は次の 3 つ。

- A. Spinel 同梱の `openssl` パッケージ(`OpenSSL::SSL::SSLSocket`)を使う。ビルド要件(libssl-dev)を許容できれば最短だが、動作は未検証。
- B. FFI で libssl に直接つなぐ。CyberTrain が SQLite で行っている方式と同じで、`ffi_source` の制約(規則 59)に従う。作業量は大きい。
- C. 平文 SMTP をローカルの中継(Postfix / msmtp / stunnel など)へ送る。実装は最小で、CyberTrain の「TLS は外に任せる」方針と一致する。運用が 1 段増える。

M0 の検証で A の動作可否を最初に確認し、不可なら B と C を比較する。C をフォールバックとして常に残すため、トランスポートは差し替え可能にしておく。

## 7. マイルストーン

- M0: 検証。TLS(A/B/C)、`TCPSocket` の挙動(`wait_readable` と書き込みの待機)、日本語件名のエンコード、`Digest` / `Base64` の可否。
- M1: メッセージ組み立て + `ScriptedTransport` + プロトコル状態機械(平文のみ)。スナップショットテスト。
- M2: TLS と認証。実サーバ(Mailpit 等)での結合テスト。
- M3: 非同期送信(`deliver_later`: メソッド経由で `Thread.new`)、リトライ方針、CyberTrain テンプレートとの連携。

## 8. 未決事項

1. TLS 方針: A を採用(決定済み。`docs/m0-findings.md` 参照)。
2. 別セッションで決めた用語・API があれば反映する(本書の命名は仮)。
3. ライセンス: MIT(決定済み)。
4. README の説明から「認証」を外した(決定済み)。

## 9. 進捗

- M0: 完了(`docs/m0-findings.md`)。
- M1: 完了。`Address` / `Mime` / `Message` / `Reply` / `Result` / `Session`(平文 + STARTTLS の台本テスト + AUTH PLAIN)/ `ScriptedTransport` / `Delivery`(`SmtpDelivery` / `LogDelivery` / `TestDelivery`)。テストは `test/*.rb` で、CRuby と Spinel の両方で同じ出力になる。依存方向は `script/check-dependencies` で確認する。
- M2: 完了(接続タイムアウトを除く)。`SocketTransport`(平文 / STARTTLS / 暗黙 TLS、`wait_readable` つき、STARTTLS 応答後の余剰バイトを拒否)、AUTH LOGIN(PLAIN が無いとき)。`integration/run-mailpit` が Mailpit に対して STARTTLS + AUTH、平文、ループバック認証を実行し、保存された件名・表示名・ドットスタッフィングを確認する。
- 接続タイムアウト: 完了。`SocketTransport` は connect / 待機ごと / 全体の 3 種の期限を持つ(`test/socket_transport.rb`)。macOS では拒否された接続も「書き込み可」になるため、`SO_ERROR` で確認する。
- M3: 完了(テンプレート連携を除く)。`RetryPolicy`(指数バックオフ、上限つき、ジッタなし)、`RetryingDelivery`(4xx と接続断=421 を再試行、5xx と `InvalidMessage` / `InsecureConnection` / `ProtocolError` は再試行しない)、`DeliveryFactory` / `SmtpDeliveryFactory`(試行ごとに新しいトランスポート)、`Delivery#deliver_later` と `DeliveryJob`(スレッド内の例外はジョブの失敗 Result になる)。`test/retry.rb` は Spinel で 30 回繰り返して安定していた。
- テンプレート連携: このライブラリには入れない。CyberTrain 側でテンプレートを描画し、`Message#text_body` / `html_body` に渡す薄い層を、CyberTrain のリポジトリか別パッケージに置く(本体に依存させないため)。
- 残り: XOAUTH2、添付ファイル、キューの永続化。
