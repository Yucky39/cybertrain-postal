require_relative "support/harness"
require "cybertrain/postal"

include Cybertrain::Postal

def protocol_error?(lines)
  r = Reply.new
  lines.each { |l| r.add_line(l) }
  false
rescue ProtocolError
  true
end

test "a single-line reply is complete" do
  r = Reply.new
  assert r.add_line("250 OK")
  assert_equal 250, r.code
  assert_equal "OK", r.text
  assert r.positive?
end

test "a multi-line reply completes on the space separator" do
  r = Reply.new
  assert !r.add_line("250-mail.example.com")
  assert !r.add_line("250-STARTTLS")
  assert r.add_line("250 AUTH PLAIN")
  assert_equal ["mail.example.com", "STARTTLS", "AUTH PLAIN"], r.lines
end

test "a bare code is a complete reply" do
  r = Reply.new
  assert r.add_line("354")
  assert_equal 354, r.code
end

test "malformed replies are protocol errors" do
  assert protocol_error?(["25"])
  assert protocol_error?(["abc OK"])
  assert protocol_error?(["999 nope"])
  assert protocol_error?(["250xOK"])
  assert protocol_error?(["250-a", "251 b"])
end

PostalTest.run!
