require_relative "support/harness"
require "cybertrain/postal"

include Cybertrain::Postal

def bad_address?(text)
  Address.build(text, "")
  false
rescue InvalidMessage
  true
end

test "a plain address is accepted" do
  a = Address.build("taro@example.com", "")
  assert_equal "taro@example.com", a.addr
  assert_equal "taro@example.com", a.to_header
end

test "a display name is encoded in the header" do
  a = Address.build("taro@example.com", "山田 太郎")
  assert a.to_header.start_with?("=?UTF-8?B?")
  assert a.to_header.end_with?(" <taro@example.com>")
end

test "malformed addresses are refused" do
  assert bad_address?("")
  assert bad_address?("no-at-sign")
  assert bad_address?("@example.com")
  assert bad_address?("taro@")
  assert bad_address?("a@b@example.com")
  assert bad_address?("a b@example.com")
  assert bad_address?("a@example..com")
  assert bad_address?("<a@example.com>")
  assert bad_address?("taro@example.com\r\nBcc: x@example.com")
  assert bad_address?("山田@example.com")
end

PostalTest.run!
