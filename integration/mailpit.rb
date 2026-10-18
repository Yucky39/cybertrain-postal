# End-to-end check against a running Mailpit; run via integration/run-mailpit.
# usage: mailpit_check MODE PORT   (MODE: plain | starttls | auth | later | retry | spool)
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
factory.verify_cert = false
factory.require_tls = (mode == "starttls" || mode == "later" || mode == "spool")
factory.credentials("user", "secret") unless mode == "plain" || mode == "retry"
factory.timeout = 5
factory.connect_timeout = 2

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
