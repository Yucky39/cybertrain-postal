require_relative "support/harness"
require "cybertrain/postal"

include Cybertrain::Postal

def build
  m = Message.new(Address.build("noreply@example.com", ""))
  m.add_to(Address.build("taro@example.com", ""))
  m.subject = "Hi"
  m.text_body = "Body"
  m.date = "Sun, 18 Oct 2026 10:00:00 +0000"
  m.message_id = "id@example.com"
  m
end

GOOD = ["220 mx ready", "250-mx", "250 8BITMIME", "250 sender ok", "250 rcpt ok",
        "354 go ahead", "250 queued", "221 bye"]

test "a plain delivery follows the SMTP dialogue" do
  t = ScriptedTransport.new(GOOD, false, false)
  r = Session.new(t, "client.example.com", false).deliver(build, "", "")
  assert r.ok?
  assert_equal 250, r.code
  assert_equal ["taro@example.com"], r.accepted
  sent = t.sent
  assert sent.start_with?("EHLO client.example.com\r\nMAIL FROM:<noreply@example.com>\r\nRCPT TO:<taro@example.com>\r\nDATA\r\n")
  assert sent.include?("\r\n.\r\nQUIT\r\n")
  assert t.closed?
end

test "dot-stuffing doubles a leading dot on every line" do
  assert_equal "..a\r\nb\r\n..c\r\n", Session.dot_stuff(".a\r\nb\r\n.c")
end

test "a rejected recipient is reported and delivery continues for the rest" do
  script = ["220 mx", "250 mx", "250 ok", "250 ok", "550 no such user", "354 go", "250 queued", "221 bye"]
  m = build
  m.add_cc(Address.build("ghost@example.com", ""))
  r = Session.new(ScriptedTransport.new(script, false, false), "c", false).deliver(m, "", "")
  assert r.ok?
  assert_equal ["taro@example.com"], r.accepted
  assert_equal ["ghost@example.com"], r.rejected
end

test "no accepted recipient is a failure that never sends DATA" do
  script = ["220 mx", "250 mx", "250 ok", "550 no such user", "250 reset", "221 bye"]
  t = ScriptedTransport.new(script, false, false)
  r = Session.new(t, "c", false).deliver(build, "", "")
  assert !r.ok?
  assert r.permanent?
  assert_equal 550, r.code
  assert !t.sent.include?("DATA")
end

test "a 4xx reply is a temporary failure" do
  script = ["220 mx", "250 mx", "250 ok", "250 ok", "354 go", "451 try later", "221 bye"]
  r = Session.new(ScriptedTransport.new(script, false, false), "c", false).deliver(build, "", "")
  assert r.temporary?
  assert_equal 451, r.code
end

test "STARTTLS upgrades the stream and EHLO is repeated" do
  script = ["220 mx", "250-mx", "250 STARTTLS", "220 ready", "250 mx", "250 ok", "250 ok", "354 go", "250 queued", "221 bye"]
  t = ScriptedTransport.new(script, false, false)
  r = Session.new(t, "c", true).deliver(build, "", "")
  assert r.ok?
  assert t.secure?
  assert t.sent.include?("STARTTLS\r\nEHLO c\r\n")
end

test "a failed TLS upgrade never falls back to plain text" do
  script = ["220 mx", "250-mx", "250 STARTTLS", "220 ready"]
  t = ScriptedTransport.new(script, false, false)
  t.tls_ok = false
  refused = false
  begin
    Session.new(t, "c", false).deliver(build, "", "")
  rescue InsecureConnection
    refused = true
  end
  assert refused
  assert !t.sent.include?("MAIL FROM")
end

test "require_tls refuses a server that does not offer STARTTLS" do
  t = ScriptedTransport.new(["220 mx", "250 mx"], false, false)
  refused = false
  begin
    Session.new(t, "c", true).deliver(build, "", "")
  rescue InsecureConnection
    refused = true
  end
  assert refused
end

test "credentials are never sent over an unencrypted remote connection" do
  script = ["220 mx", "250-mx", "250 AUTH PLAIN"]
  t = ScriptedTransport.new(script, false, false)
  refused = false
  begin
    Session.new(t, "c", false).deliver(build, "user", "secret")
  rescue InsecureConnection
    refused = true
  end
  assert refused
  assert !t.sent.include?("AUTH")
end

test "AUTH PLAIN over TLS sends base64 of NUL user NUL password" do
  script = ["220 mx", "250-mx", "250 AUTH PLAIN LOGIN", "235 ok", "250 ok", "250 ok", "354 go", "250 queued", "221 bye"]
  t = ScriptedTransport.new(script, true, false)
  r = Session.new(t, "c", false).deliver(build, "user", "secret")
  assert r.ok?
  assert t.sent.include?("AUTH PLAIN " + Base64.strict_encode64("\0user\0secret") + "\r\n")
end

test "a loopback connection may authenticate without TLS" do
  script = ["220 mx", "250-mx", "250 AUTH PLAIN", "235 ok", "250 ok", "250 ok", "354 go", "250 queued", "221 bye"]
  r = Session.new(ScriptedTransport.new(script, false, true), "c", false).deliver(build, "user", "secret")
  assert r.ok?
end

test "a rejected login is a failure" do
  script = ["220 mx", "250-mx", "250 AUTH PLAIN", "535 bad credentials", "221 bye"]
  r = Session.new(ScriptedTransport.new(script, true, false), "c", false).deliver(build, "user", "wrong")
  assert !r.ok?
  assert_equal 535, r.code
end

test "a dropped connection raises ConnectionLost" do
  lost = false
  begin
    Session.new(ScriptedTransport.new(["220 mx", "250 mx"], false, false), "c", false).deliver(build, "", "")
  rescue ConnectionLost
    lost = true
  end
  assert lost
end

PostalTest.run!
