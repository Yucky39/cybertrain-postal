# cybertrain-postal

SMTP mail delivery library for [CyberTrain](https://github.com/saeki-mototsune/CyberTrain) (Spinel).

Status: pre-alpha. Design notes: [docs/design.md](docs/design.md).

```ruby
require "cybertrain/postal"
require "cybertrain/postal/smtp_factory"
include Cybertrain::Postal

m = Message.new(Address.build("noreply@example.com", "Example"))
m.add_to(Address.build("taro@example.com", "太郎"))
m.subject = "こんにちは"
m.text_body = "本文"

factory = SmtpDeliveryFactory.new("smtp.example.com", 587, false, "app.example.com")
factory.credentials("user", "secret")
mailer = RetryingDelivery.new(factory, RetryPolicy.new(5, 2.0, 60.0), SystemSleeper.new)

result = mailer.deliver(m)       # Result: ok? / temporary? / permanent?
mailer.deliver!(m)               # raises DeliveryFailed on failure
job = mailer.deliver_later(m)    # runs on its own thread
job.wait
```

- STARTTLS is used whenever the server offers it and is never downgraded; credentials are not sent without TLS (loopback excepted).
- Durable queue: `QueueDelivery.new(Spool.new(dir))` accepts a message onto disk (Maildir-style, one file per message); run `SpoolRunner.new(spool, factory, policy).run_once(Time.now.to_i)` from a loop or a scheduler to send, retry with backoff, and park permanent failures in `failed/`.
- Attachments: `m.attach(Attachment.build("請求書.pdf", "application/pdf", bytes))`; pass a content id as the fourth argument for an inline image referenced from the HTML body as `cid:...`. A message larger than the server's advertised `SIZE` is refused before it is sent.
- XOAUTH2: `factory.auth_mechanism = "XOAUTH2"; factory.credentials(user, access_token)`. Obtaining and renewing the token is up to the caller.
- `LogDelivery` and `TestDelivery` send nothing, for development and tests.
- Build: Spinel 2026.09.12. On macOS with Homebrew, `export LIBRARY_PATH=$(brew --prefix openssl@3)/lib CPATH=$(brew --prefix openssl@3)/include`.
- Tests: `spin test`. End-to-end against Mailpit: `integration/run-mailpit`.

## License

MIT
