require_relative "support/harness"
require "cybertrain/postal"

include Cybertrain::Postal

def raises_invalid?(&block)
  block.call
  false
rescue InvalidMessage
  true
end

test "plain ASCII text is left alone" do
  assert_equal "Hello world", Mime.encode_text("Hello world")
end

test "non-ASCII text becomes an encoded-word" do
  assert_equal "=?UTF-8?B?44GT44KT44Gr44Gh44Gv?=", Mime.encode_text("こんにちは")
end

test "long non-ASCII text splits on character boundaries" do
  text = "日本語のとても長い件名です。" * 4
  encoded = Mime.encode_text(text)
  words = encoded.split("\r\n ")
  assert words.length > 1
  words.each { |w| assert w.bytesize <= 75 }
  decoded = +""
  words.each { |w| decoded << Base64.strict_decode64(w.byteslice(10, w.bytesize - 12)) }
  assert_equal text, decoded.force_encoding("UTF-8")
end

test "header values with CR or LF are refused" do
  assert raises_invalid? { Mime.encode_text("a\r\nBcc: x@example.com") }
  assert raises_invalid? { Mime.encode_text("a\nb") }
end

test "display names with specials are quoted" do
  assert_equal "Taro Yamada", Mime.display_name("Taro Yamada")
  assert_equal "\"Yamada, Taro\"", Mime.display_name("Yamada, Taro")
end

test "base64 body wraps at 76 columns with CRLF" do
  body = Mime.base64_body("x" * 100)
  lines = body.split("\r\n")
  assert_equal 76, lines[0].bytesize
  assert body.end_with?("\r\n")
end

test "crlf normalises line endings" do
  assert_equal "a\r\nb\r\nc", Mime.crlf("a\nb\r\nc")
end

PostalTest.run!
