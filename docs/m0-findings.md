# M0 検証結果

環境: Spinel 2026.09.12(`~/.local/src/spinel` でビルド)、macOS arm64、Homebrew の openssl@3。
コードは `spikes/` にある。ビルドは `spinel spikes/<name>.rb -o build/<name>`。

## 結果

| 項目 | 結果 |
| --- | --- |
| `Base64.strict_encode64` | 動作 |
| `Digest::SHA256.hexdigest` | 動作(`abc` の値が一致) |
| RFC 2047(`=?UTF-8?B?...?=`)の日本語件名 | 動作。`bytesize` / `byteslice` も期待どおり |
| `TCPSocket` + `wait_readable(timeout)` | 動作。無通信は nil、受信後は ready、切断後は `EOFError` |
| TLS 方針 A(同梱 `openssl` パッケージの `SSLSocket`) | **動作**。暗黙 TLS(465)で smtp.gmail.com に接続し、証明書をシステムのストアで検証して 220 バナーを受信した |
| 証明書検証 | 自己署名証明書は既定で `certificate verify failed` となり拒否される。`VERIFY_NONE` を明示した場合のみ通る |

## 結論

- TLS は方針 A で進める。B(FFI)と C(中継)は不要。C はトランスポートの差し替えで残す。
- 方針 A のビルド要件は libssl のヘッダとライブラリである。Homebrew の openssl@3 は標準の検索パスに無いため、macOS では `LIBRARY_PATH=$(brew --prefix openssl@3)/lib CPATH=$(brew --prefix openssl@3)/include` が必要だった。ビルド手順に書く。
- `SSLContext` で使えるのは `verify_mode` と `verify_hostname` のみ。クライアント証明書や最小 TLS バージョンの指定は現状できない。
- `ssl.hostname=` を必ず設定する(SNI と証明書のホスト名検証に使われる)。

## 未検証(M1 / M2 で確認)

- STARTTLS: 平文で EHLO / STARTTLS を交わした後に、同じ `TCPSocket` へ `SSLSocket` をかぶせる流れ。
- `connect_nonblock` による接続タイムアウト。
- 実サーバ(Mailpit 等)での AUTH と配送。
