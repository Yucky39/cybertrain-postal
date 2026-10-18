require_relative "support/harness"
require "cybertrain/postal"

include Cybertrain::Postal

def build
  m = Message.new(Address.build("noreply@example.com", ""))
  m.add_to(Address.build("taro@example.com", ""))
  m.add_bcc(Address.build("audit@example.com", ""))
  m.subject = "Hi"
  m.text_body = "Body"
  m.date = "Sun, 18 Oct 2026 10:00:00 +0000"
  m.message_id = "id@example.com"
  m
end

GOOD = ["220 mx ready", "250-mx", "250 8BITMIME", "250 sender ok", "250 rcpt ok",
        "250 rcpt ok", "354 go ahead", "250 queued", "221 bye"]
BAD = ["220 mx", "250 mx", "250 ok", "250 ok", "250 ok", "354 go", "550 spam", "221 bye"]

test "SmtpDelivery#deliver returns the Result" do
  t = ScriptedTransport.new(GOOD, false, false)
  r = SmtpDelivery.new(t, "c.example.com", "", "", false).deliver(build)
  assert r.ok?
  assert_equal 250, r.code
  assert_equal ["taro@example.com", "audit@example.com"], r.accepted
end

test "deliver! returns the Result on success" do
  t = ScriptedTransport.new(GOOD, false, false)
  r = SmtpDelivery.new(t, "c", "", "", false).deliver!(build)
  assert r.ok?
end

def failing_text
  t = ScriptedTransport.new(BAD, false, false)
  begin
    SmtpDelivery.new(t, "c", "", "", false).deliver!(build)
    "no raise"
  rescue DeliveryFailed => e
    e.message
  end
end

test "deliver! raises DeliveryFailed with code and text" do
  assert_equal "550 spam", failing_text
end

test "deliver reports a permanent failure without raising" do
  t = ScriptedTransport.new(BAD, false, false)
  r = SmtpDelivery.new(t, "c", "", "", false).deliver(build)
  assert !r.ok?
  assert r.permanent?
end

test "TestDelivery records messages and sends nothing" do
  d = TestDelivery.new
  r = d.deliver(build)
  assert r.ok?
  assert_equal 1, d.messages.length
  assert_equal "Hi", d.messages[0].subject
  d.clear
  assert_equal 0, d.messages.length
end

test "LogDelivery logs counts only" do
  d = LogDelivery.new(false)
  r = d.deliver(build)
  assert r.ok?
  assert_equal 1, d.lines.length
  assert d.lines[0].start_with?("mail logged: recipients=2 bytes=")
  assert !d.lines[0].include?("taro")
  assert !d.lines[0].include?("Hi")
end

test "a Delivery subclass without perform fails cleanly" do
  r = Delivery.new.deliver(build)
  assert !r.ok?
  assert_equal 0, r.code
end

PostalTest.run!
