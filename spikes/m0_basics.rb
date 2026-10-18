# M0: Base64 / Digest / HMAC availability and RFC 2047 encoding of Japanese.
require "base64"
require "digest"

puts Base64.strict_encode64("hello\r\n")
puts Digest::SHA256.hexdigest("abc")

subject = "日本語の件名"
enc = "=?UTF-8?B?" + Base64.strict_encode64(subject) + "?="
puts enc
puts subject.bytesize
puts subject.byteslice(0, 3)
