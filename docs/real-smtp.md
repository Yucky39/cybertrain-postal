# Trying a real SMTP provider

The integration tests use Mailpit, which accepts anything. This is how to check
one real provider (Gmail, SES, ...) with TLS and authentication. It sends **one**
test message, from your own machine, with your own credentials; nothing is
stored, and the password is never printed.

Needs Spinel on `PATH` (`export PATH=$HOME/.cybertrain/spinel/<release>/bin:$PATH`) and, on macOS, Homebrew's OpenSSL (`brew install openssl@3`). The script points the compiler at it when `LIBRARY_PATH` is not set; if you set your own, it is left alone.

## Run it

First type the password without echoing it, so it stays out of your shell
history. Run this line **on its own**: if you paste more lines with it, the shell
reads them as the password and nothing is sent. Type the password, press Enter
(nothing is shown):

```sh
read -s POSTAL_SMTP_PASSWORD; export POSTAL_SMTP_PASSWORD
```

Then the check itself:

```sh
POSTAL_SMTP_HOST=smtp.gmail.com \
POSTAL_SMTP_USER=you@gmail.com \
POSTAL_MAIL_FROM=you@gmail.com \
POSTAL_MAIL_TO=you@gmail.com \
script/check-real-smtp
```

| Provider | Host | Port / TLS | User, password |
| --- | --- | --- | --- |
| Gmail | `smtp.gmail.com` | 587, STARTTLS (default) | your address and an [app password](https://support.google.com/accounts/answer/185833) (2-step verification on) |
| Amazon SES | `email-smtp.<region>.amazonaws.com` | 587, STARTTLS | the SMTP credentials made in the SES console (not your AWS keys); `POSTAL_MAIL_FROM` must be a verified identity |
| Implicit TLS | any | `POSTAL_SMTP_PORT=465 POSTAL_SMTP_TLS=implicit` | as the provider says |
| XOAUTH2 | Gmail / Microsoft | as above, plus `POSTAL_SMTP_AUTH=XOAUTH2` | the access token as `POSTAL_SMTP_PASSWORD` |

All settings are listed at the top of `integration/real_smtp.rb`.

## What the output means

```
server:  smtp.gmail.com:587 (STARTTLS required, certificate checks on)
auth:    PLAIN/LOGIN as you@gmail.com
result:  ok=true code=250 2.0.0 OK ...
```

- `ok=true code=250`: the server accepted the message. Check the inbox too.
- `refused to continue: ...`: no STARTTLS offered, the handshake or certificate
  check failed, or credentials would have gone over an unencrypted connection.
  Certificate and host-name checks stay on; nothing here turns them off.
- `refused to continue: TLS could not be established: the handshake timed out ...`:
  the server answered STARTTLS but then never answered the TLS hello. On some
  networks the hello of OpenSSL 3.5 (it carries a hybrid post-quantum key share and
  is much larger) is dropped on the way. Run again with
  `POSTAL_SMTP_CLASSICAL_GROUPS=1 script/check-real-smtp ...`, which limits the key
  exchange to X25519 and P-256 (`integration/classical-groups.cnf`). For your own
  program, set `OPENSSL_CONF` to that file in the environment of the process that
  sends. Certificate checks are not affected.
- `ok=false code=535` (or similar): the server refused the login.
- `refused: someone@...`: the server accepted the message but not that recipient.

## What to look at in the received message

Use the mail client's "show original":

1. The subject shows `日本語` correctly (encoded-word) and the body is readable.
2. The third body line starts with a dot: `.この行は先頭がドットです。` (dot-stuffing).
3. `From`, `To`, `Date` and `Message-ID` are there, and the provider did not put
   the message in spam for a missing header.

## Results

Add a row when you have tried a provider (date, provider, port, auth, result):

| Date | Provider | Port / TLS | Auth | Result |
| --- | --- | --- | --- | --- |
| 2026-10-29 | Gmail (`smtp.gmail.com`, app password) | 587, STARTTLS, certificate checks on | PLAIN/LOGIN | accepted: `ok=true code=250`. Needed `POSTAL_SMTP_CLASSICAL_GROUPS=1` on the network it was tried on (without it the TLS hello was dropped). The received message's subject and body were not inspected. |
