# End-to-end check against a running Mailpit; run via integration/run-mailpit.
# usage: mailpit_check MODE PORT   (MODE: plain | starttls | verify | stalltls | auth | later | retry | spool | attach)
require "cybertrain/postal"
require "cybertrain/postal/smtp_factory"

include Cybertrain::Postal

mode = ARGV[0]
port = ARGV[1].to_i

m = Message.new(Address.build("noreply@example.com", "サイバートレイン"))
m.add_to(Address.build("taro@example.com", "太郎"))
m.subject = "M2 結合テスト " + mode
m.text_body = "こんにちは。\r\n.この行は先頭がドットです。\r\n"
m.date = "Sun, 18 Oct 2026 10:00:00 +0900"
m.message_id = mode + "@example.com"

factory = SmtpDeliveryFactory.new("127.0.0.1", port, false, "client.example.com")
# "verify" keeps the default (certificate checks on) to see a self-signed
# certificate refused; every other mode turns the checks off for Mailpit's.
factory.verify_cert = false unless mode == "verify"
factory.require_tls = (mode == "verify" || mode == "stalltls" || mode == "starttls" || mode == "later" || mode == "spool" || mode == "attach")
factory.credentials("user", "secret") unless mode == "plain" || mode == "retry" || mode == "verify" || mode == "stalltls"
factory.timeout = 5
factory.connect_timeout = 2

if mode == "verify"
  # Mailpit's certificate is self-signed for CN=localhost: with the checks on,
  # STARTTLS must fail and nothing may be sent in the clear.
  refused = false
  begin
    r = factory.new_delivery.deliver(m)
    puts "ok=#{r.ok?} code=#{r.code}"
  rescue InsecureConnection
    refused = true
  end
  puts "refused=#{refused}"
  exit(refused ? 0 : 1)
end

if mode == "stalltls"
  # A server that says "go ahead" to STARTTLS and then never answers the TLS
  # hello (what a network dropping the hello looks like): the client must give
  # up with a reason once its timeout is over, not wait for ever.
  factory.verify_cert = false
  factory.timeout = 2
  reason = ""
  begin
    factory.new_delivery.deliver(m)
  rescue InsecureConnection => e
    reason = e.message
  end
  puts "reason=#{reason}"
  exit(reason.include?("timed out") ? 0 : 1)
end

if mode == "attach"
  data = [137, 80, 78, 71, 0, 255, 254, 1].pack("C*") * 500
  m.html_body = "<p>logo: <img src=\"cid:logo1\"></p>"
  m.attach(Attachment.build("請求書 2026.pdf", "application/pdf", data))
  m.attach(Attachment.build("logo.png", "image/png", data, "logo1"))
  r = SmtpDelivery.new(SocketTransport.new("127.0.0.1", port, false, 2, 5, 30, false), "client.example.com", "user", "secret", true).deliver(m)
  puts "ok=#{r.ok?} code=#{r.code} bytes=#{data.bytesize}"
  exit(r.ok? ? 0 : 1)
end

if mode == "spool"
  require "tmpdir"
  spool = Spool.new(Dir.mktmpdir("postal-it"))
  q = QueueDelivery.new(spool).deliver(m)
  runner = SpoolRunner.new(spool, factory, RetryPolicy.new(3, 0.1, 1.0))
  report = runner.run_once(Time.now.to_i)
  puts "queued=#{q.ok?} delivered=#{report.delivered} left=#{spool.count('new')}"
  exit(q.ok? && report.delivered == 1 && spool.count("new") == 0 ? 0 : 1)
end

if mode == "retry"
  # nothing listens on this port: every attempt loses the connection
  sleeper = Sleeper.new
  retrying = RetryingDelivery.new(factory, RetryPolicy.new(3, 0.1, 1.0), sleeper)
  r = retrying.deliver(m)
  puts "ok=#{r.ok?} code=#{r.code} attempts=#{retrying.attempts}"
  exit(r.code == 421 && retrying.attempts == 3 ? 0 : 1)
end

retrying = RetryingDelivery.new(factory, RetryPolicy.new(3, 0.1, 1.0), SystemSleeper.new)
r = mode == "later" ? retrying.deliver_later(m).wait : retrying.deliver(m)
puts "ok=#{r.ok?} code=#{r.code} attempts=#{retrying.attempts}"
exit(1) unless r.ok?
