# cybertrain-postal

An SMTP mail library written for [Spinel](https://github.com/matz/spinel), made for [CyberTrain](https://github.com/saeki-mototsune/CyberTrain) applications but independent of it: it needs no framework code, only Spinel's standard library.

**Status: pre-alpha.** It sends real mail (checked against Mailpit), but the API may still change and it has not had a security review.

No `eval`, `send` or `method_missing` anywhere, as Spinel requires. Messages are built as plain Ruby objects; delivery strategies (`SmtpDelivery`, a retrying wrapper, a disk queue, a log, a test double) share one small interface.

## Requirements

- Spinel 2026.10.27.7020 (`cybertrain setup` installs it; so does building [Spinel](https://github.com/matz/spinel) yourself).
- OpenSSL headers and library, **only for the part that opens an SMTP connection** (see "Do not link OpenSSL into a web server"). On macOS with Homebrew:

  ```sh
  export LIBRARY_PATH=$(brew --prefix openssl@3)/lib CPATH=$(brew --prefix openssl@3)/include
  ```

## Quick start

```ruby
require "cybertrain/postal"
require "cybertrain/postal/smtp_factory"   # links OpenSSL; see below
include Cybertrain::Postal

m = Message.new(Address.build("noreply@example.com", "Example"))
m.add_to(Address.build("taro@example.com", "太郎"))
m.subject = "こんにちは"
m.text_body = "本文"

factory = SmtpDeliveryFactory.new("smtp.example.com", 587, false, "app.example.com")
factory.credentials("user", "secret")
mailer = RetryingDelivery.new(factory, RetryPolicy.new(5, 2.0, 60.0), SystemSleeper.new)

result = mailer.deliver(m)       # a Result: ok? / temporary? / permanent?, with the SMTP code
mailer.deliver!(m)               # raises DeliveryFailed instead
job = mailer.deliver_later(m)    # runs on its own thread
job.wait
```

`SmtpDeliveryFactory.new(host, port, implicit_tls, local_hostname)`: `implicit_tls` is `true` for a TLS-from-the-start port (465) and `false` for 587 / 25, where STARTTLS is used.

## Messages

- Plain text, or text plus HTML as `multipart/alternative`. Bodies are UTF-8 and base64-encoded; non-ASCII subjects and display names become RFC 2047 encoded-words, split on character boundaries.
- Attachments: `m.attach(Attachment.build("請求書.pdf", "application/pdf", bytes))`. Pass a content id as the fourth argument for an inline image that the HTML body references as `cid:...`. Filenames are encoded per RFC 2231. A message larger than the server's advertised `SIZE` is refused before it is sent.
- `m.add_to`, `add_cc`, `add_bcc`. Bcc recipients are in the envelope only, never in a header.
- Anything that could inject a header (CR, LF or NUL in a header value, or in an address) raises `InvalidMessage`. Addresses must be ASCII (no SMTPUTF8).
- `m.valid_for = seconds`: a queued message that is still undelivered after this long is moved to `failed/` instead of being sent, and a retry that would fall after the deadline is not scheduled (a reset link that arrives a day late helps nobody).

## TLS and authentication

- STARTTLS is used whenever the server offers it and is **never downgraded**: if the upgrade fails, nothing is sent. `factory.require_tls = true` (the default) also refuses a server that does not offer it; set it to `false` only for a relay on the same machine.
- Certificates are verified (`factory.verify_cert = false` turns that off, for a test server with a self-signed certificate).
- Credentials are sent only over TLS, or to a loopback address. The mechanism is PLAIN, or LOGIN when only that is offered. For XOAUTH2: `factory.auth_mechanism = "XOAUTH2"; factory.credentials(user, access_token)`; obtaining and renewing the token is up to the caller.
- Timeouts: connect 10 s, each read 30 s, whole delivery 120 s (`factory.connect_timeout`, `timeout`, `total_timeout`).

## Retrying, and a durable queue

`RetryingDelivery` retries **temporary** (4xx) failures and lost connections, with exponential backoff (`RetryPolicy.new(max_attempts, base_delay, max_delay)`). Permanent (5xx) failures, an invalid message and a refused TLS upgrade are not retried: they would fail the same way again.

For mail that must not be lost when the process stops, queue it on disk and send it from another process:

```ruby
spool = Spool.new("storage/mail_spool")
QueueDelivery.new(spool).deliver(m)    # answers 250 "queued ..." once the file is safely written

# elsewhere, in a loop or on a schedule:
runner = SpoolRunner.new(spool, factory, RetryPolicy.new(8, 30.0, 3600.0))
runner.run_once(Time.now.to_i)         # sends what is due, reschedules temporary failures
spool.recover_stale(Time.now.to_i, 600)  # takes back messages a crashed worker had claimed
```

The spool is Maildir-style: one file per message, and every state change is a rename, so a crash never leaves a half-written message (`tmp/`, `new/`, `active/`, `failed/`). Permanent failures and messages that ran out of attempts are parked in `failed/` for inspection (`Spool#purge_failed(now, max_age)` removes old ones). Directories are created owner-only (0700) and files 0600, because a queued message can hold a secret such as a reset link; the web application and the worker must therefore run as the same user.

## Do not link OpenSSL into a web server

Spinel's `openssl` package is needed for SMTP over TLS, but at Spinel 2026.09.12 a CyberTrain web application that requires `openssl` fails on every request ([CyberTrain#27](https://github.com/saeki-mototsune/CyberTrain/issues/27)). So the library is split on purpose:

- `require "cybertrain/postal"` loads the core (messages, the protocol, the spool, `QueueDelivery`) and **does not load OpenSSL**. A web application can use it to queue mail.
- `require "cybertrain/postal/smtp_factory"` (which loads `socket_transport` and OpenSSL) belongs in a **separate program**, the worker that runs `SpoolRunner`.

[cybertrain-kaisatsu](https://github.com/Yucky39/cybertrain-kaisatsu) generates exactly this arrangement (`kaisatsu install --postal`); the contract between the two is in [docs/integration-kaisatsu.md](docs/integration-kaisatsu.md) (Japanese). The two libraries do not depend on each other.

## For development and tests

- `LogDelivery` prints instead of sending; `TestDelivery` records what was "sent".
- `ScriptedTransport` plays a scripted SMTP dialogue and records what the client wrote, to test the protocol without a network.

## What is checked

- `spin test` runs the unit tests under Spinel (10 programs): encoding, addresses, replies, the SMTP dialogue (including every TLS and credential refusal), retrying, the spool, and sockets.
- `integration/run-mailpit` runs end-to-end checks against [Mailpit](https://github.com/axllent/mailpit): STARTTLS with authentication, plain SMTP, authentication to a loopback server, attachments, `deliver_later`, the spool and runner, and retry after a lost connection.
- CI runs both on Linux and macOS, and `script/check-dependencies` makes sure the library never requires CyberTrain itself.

## Known limits

- An SMTP client only: no DKIM signing, no bounce handling, no SMTPUTF8.
- One connection per message (a fresh transport serves one delivery); no pipelining.
- XOAUTH2 tokens are not refreshed for you.
- The library has no template or HTML-to-text support.
- Not yet run against a real provider (Gmail, SES, ...) with TLS and authentication: the integration tests use Mailpit only ([#5](https://github.com/Yucky39/cybertrain-postal/issues/5)).
- If some recipients are refused but the message is accepted, the delivery counts as a success and the refused addresses are not reported or kept ([#3](https://github.com/Yucky39/cybertrain-postal/issues/3)).
- Certificate and host-name checks rely on Spinel's `SSLContext` defaults instead of being set explicitly, and the minimum TLS version cannot be chosen ([#4](https://github.com/Yucky39/cybertrain-postal/issues/4)).

## Documentation

- [docs/design.md](docs/design.md): design notes (Japanese).
- [docs/m0-findings.md](docs/m0-findings.md): what was measured before building (Japanese).

## License

MIT
