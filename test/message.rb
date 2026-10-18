require_relative "support/harness"
require "cybertrain/postal"

include Cybertrain::Postal

def build
  m = Message.new(Address.build("noreply@example.com", "Example"))
  m.add_to(Address.build("taro@example.com", ""))
  m.subject = "Welcome"
  m.text_body = "Hello\nWorld"
  m.date = "Sun, 18 Oct 2026 10:00:00 +0000"
  m.message_id = "fixed-id@example.com"
  m.boundary = "BOUNDARY"
  m
end

test "plain text message renders headers and a base64 body" do
  out = build.render
  assert out.include?("From: Example <noreply@example.com>\r\n")
  assert out.include?("To: taro@example.com\r\n")
  assert out.include?("Subject: Welcome\r\n")
  assert out.include?("Message-ID: <fixed-id@example.com>\r\n")
  assert out.include?("Content-Type: text/plain; charset=UTF-8\r\n")
  assert out.end_with?(Mime.base64_body("Hello\r\nWorld"))
  assert !out.include?("Bcc")
end

test "an HTML body makes a multipart/alternative message" do
  m = build
  m.html_body = "<p>Hello</p>"
  out = m.render
  assert out.include?("Content-Type: multipart/alternative; boundary=\"BOUNDARY\"\r\n")
  assert out.include?("Content-Type: text/html; charset=UTF-8\r\n")
  assert out.end_with?("--BOUNDARY--\r\n")
end

test "bcc recipients are in the envelope but never in a header" do
  m = build
  m.add_bcc(Address.build("secret@example.com", ""))
  assert_equal ["taro@example.com", "secret@example.com"], m.recipient_addrs
  assert !m.render.include?("secret@example.com")
end

test "a subject with a newline cannot inject a header" do
  m = build
  m.subject = "Hi\r\nBcc: evil@example.com"
  failed = false
  begin
    m.render
  rescue InvalidMessage
    failed = true
  end
  assert failed
end

test "a message without recipients is refused" do
  m = Message.new(Address.build("noreply@example.com", ""))
  failed = false
  begin
    m.render
  rescue InvalidMessage
    failed = true
  end
  assert failed
end

PostalTest.run!
