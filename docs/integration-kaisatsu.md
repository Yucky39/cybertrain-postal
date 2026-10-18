# cybertrain-kaisatsu との通知の受け口

改札(kaisatsu)は `Cybertrain::Kaisatsu::Notifier` という抽象クラスでメール送信を要求し、ポスタルはそれを実装側(アプリ)が結ぶ。**両ライブラリは互いに依存しない。** 結び目は、改札が生成するアプリ側のコード(`PostalNotifier` と `bin/mail_worker.rb`)にある。

## 構成

```
  web バイナリ                                   mail_worker バイナリ
  ┌─────────────────────────┐                   ┌──────────────────────────────┐
  │ Kaisatsu → Notifier      │   スプール        │ SpoolRunner                  │
  │   PostalNotifier         │  (ディレクトリ)   │   SmtpDeliveryFactory        │
  │     QueueDelivery ───────┼──► new/*.mail ───►│     SocketTransport (OpenSSL)│──► SMTP
  └─────────────────────────┘                   └──────────────────────────────┘
   require "cybertrain/postal"                    + "cybertrain/postal/smtp_factory"
   (OpenSSL にリンクしない)                       (OpenSSL にリンクする)
```

- web 側は**キューに積むだけ**で、SMTP には触れない。応答はメール送信の成否・遅延に左右されず、アカウントの有無でも変わらない(改札の方針)。
- 送信は別プログラムが行う。理由は、OpenSSL を `require` したバイナリでは `String#getbyte` が `OpenSSL::Buffering#getbyte` と衝突し、CyberTrain の web サーバが全リクエストで `NoMethodError` になるため(Spinel 2026.09.12)。ポスタルの本体は `getbyte` をやめたので衝突しないが、CyberTrain 側の呼び出しが残っている。**上流(CyberTrain / Spinel)への報告事項。**

## 契約

### 改札 → ポスタル

| 項目 | 内容 |
| --- | --- |
| 受け口 | `Delivery#deliver(message)` → `Result`。web 側は `QueueDelivery`。成功は「ディスクに載った」ことで、送信済みではない |
| 失敗の扱い | `Result#ok?` が偽、または `InvalidMessage`(宛先・件名のヘッダ注入など)。通知の失敗でユーザー向けの応答を変えない。ログには宛先もリンクも出さない |
| 有効期限 | `message.valid_for = 秒`。超えたメールは送らずに `failed/` へ移す。再試行が期限を越える場合もその場で打ち切る |
| 推奨値 | パスワード再設定 3600、メール確認 259200、アドレス変更リンク 86400、セキュリティ通知 86400(リンクの有効期限と同じにする) |

### ポスタルが保証すること

- **少なくとも 1 回**配送する。SMTP がメールを受理した直後に落ちた場合、`recover_stale` で戻って**重複して送られうる**。重複しても害がない内容(リンク、通知)に限る。
- 状態遷移は `rename` 一回(`tmp/` → `new/` → `active/` → 消去または `failed/`)で、書きかけのメールは見えない。ワーカーが複数でも、同じメールを 2 つのワーカーが取ることはない(`claim` は排他的)。
- 4xx と接続断は `RetryPolicy` のバックオフで再試行する。5xx と不正なメッセージは再試行しない。
- STARTTLS が使える時に平文へ降格しない。認証情報は TLS かループバック以外には送らない。
- スプールのディレクトリは 0700、メールのファイルは 0600(自分で作った場合)。

### 運用側の約束

- web とワーカーは**同じユーザー**で動かす(スプールが 0700 のため)。別ユーザーにするなら、ディレクトリを自分で作って権限を決める。
- ワーカーは定期的に `recover_stale(now, 600)` と、`purge_failed(now, 保持秒数)` を呼ぶ。`failed/` には再設定リンクのような秘密が残りうるので、保持は数日までにする。
- `Spool#count("failed")` が増え続けるなら、SMTP の設定か送信先を疑う(監視の指標にできる)。
- バウンス(送信後の不達通知)は扱わない。SPF / DKIM / DMARC は送信ドメイン側の設定で、このライブラリの外。

## 改札側への依頼(`cybertrain-kaisatsu` の生成コード)

1. `PostalNotifier#enqueue_text` で、上の推奨値の `valid_for` を設定する(メール種別ごと)。
2. `bin/mail_worker.rb` のループで `spool.purge_failed(now, 7 * 24 * 3600)` を 1 日に 1 回呼ぶ。
3. ワーカーの `spool.recover_stale(now, 600)` は現状のままでよい(1 通の送信は全体期限 120 秒を超えない)。
4. web とワーカーが同じユーザーで動く前提を `docs/install.md` に書く。

## 検証

- ポスタル: `test/spool.rb`(期限、再試行をまたぐ期限、`purge_failed`、権限)、`integration/run-mailpit`。
- 改札側の通し(登録 → 再設定要求 → スプール → ワーカー → Mailpit で受信 → リンク → 新パスワード)は、改札のセッションが Mailpit で確認済み。
- Spinel 2026.09.12 の `Dir.mkdir(path, mode)` はモードを無視する(0755 になる)。スプールは作成後に `File.chmod` で設定している。
