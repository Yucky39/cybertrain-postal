# End-to-end check against a running Mailpit; run via integration/run-mailpit.
# usage: mailpit_check MODE PORT   (MODE: plain | starttls | auth)
require "cybertrain/postal"
require "cybertrain/postal/socket_transport"

include Cybertrain::Postal

mode = ARGV[0]
port = ARGV[1].to_i

m = Message.new(Address.build("noreply@example.com", "サイバートレイン"))
m.add_to(Address.build("taro@example.com", "太郎"))
m.subject = "M2 結合テスト " + mode
m.text_body = "こんにちは。\r\n.この行は先頭がドットです。\r\n"
m.date = "Sun, 18 Oct 2026 10:00:00 +0900"
m.message_id = mode + "@example.com"

transport = SocketTransport.new("127.0.0.1", port, false, 5, false)
username = mode == "plain" ? "" : "user"
password = mode == "plain" ? "" : "secret"
delivery = SmtpDelivery.new(transport, "client.example.com", username, password, mode == "starttls")
r = delivery.deliver(m)
puts "ok=#{r.ok?} code=#{r.code} tls=#{transport.secure?}"
exit(1) unless r.ok?
