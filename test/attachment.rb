require_relative "support/harness"
require "cybertrain/postal"

include Cybertrain::Postal

BINARY = [255, 254, 0, 1, 137, 80, 78, 71].pack("C*")

def build
  m = Message.new(Address.build("noreply@example.com", ""))
  m.add_to(Address.build("taro@example.com", ""))
  m.subject = "Invoice"
  m.text_body = "See attached."
  m.date = "Sun, 18 Oct 2026 10:00:00 +0000"
  m.message_id = "fixed-id@example.com"
  m.boundary = "B"
  m
end

def rejects(filename, type, cid)
  begin
    Attachment.build(filename, type, "x", cid)
    false
  rescue InvalidMessage
    true
  end
end

test "an ASCII parameter is quoted and escaped" do
  assert_equal "filename=\"a.pdf\"", Mime.param("filename", "a.pdf")
  assert_equal "filename=\"a\\\"b.pdf\"", Mime.param("filename", "a\"b.pdf")
end

test "a non-ASCII parameter gets an ASCII fallback and an RFC 2231 form" do
  assert_equal "filename=\"___.pdf\"; filename*=UTF-8''%E8%AB%8B%E6%B1%82%E6%9B%B8.pdf", Mime.param("filename", "請求書.pdf")
end

test "filenames with control characters or path separators are refused" do
  assert rejects("", "text/plain", "")
  assert rejects("a/b.txt", "text/plain", "")
  assert rejects("..\\b.txt", "text/plain", "")
  assert rejects("a\r\nBcc: x@example.com", "text/plain", "")
  assert rejects("a" * 256, "text/plain", "")
  assert !rejects("report.csv", "text/csv", "")
end

test "malformed content types and content ids are refused" do
  assert rejects("a.txt", "text", "")
  assert rejects("a.txt", "a/b/c", "")
  assert rejects("a.txt", "text/pl ain", "")
  assert rejects("a.txt", "text/plain", "x y")
  assert rejects("a.txt", "text/plain", "<x>")
  assert !rejects("a.png", "image/png", "logo1")
end

test "one attachment makes a multipart/mixed message" do
  m = build
  m.attach(Attachment.build("data.bin", "application/octet-stream", BINARY))
  out = m.render
  assert out.include?("Content-Type: multipart/mixed; boundary=\"B_mix\"\r\n\r\n--B_mix\r\n")
  assert out.include?("Content-Type: text/plain; charset=UTF-8\r\n")
  assert out.include?("Content-Type: application/octet-stream; name=\"data.bin\"\r\n")
  assert out.include?("Content-Disposition: attachment; filename=\"data.bin\"\r\n")
  assert out.include?(Mime.base64_body(BINARY))
  assert out.end_with?("--B_mix--\r\n")
end

test "an HTML body with an attachment nests alternative inside mixed" do
  m = build
  m.html_body = "<p>Hi</p>"
  m.attach(Attachment.build("a.txt", "text/plain", "hello"))
  out = m.render
  mixed = out.index("multipart/mixed")
  alt = out.index("multipart/alternative")
  assert !mixed.nil? && !alt.nil? && mixed < alt
  assert out.include?("--B--\r\n")
  assert out.end_with?("--B_mix--\r\n")
end

test "an inline part with an HTML body makes multipart/related" do
  m = build
  m.html_body = "<img src=\"cid:logo1\">"
  m.attach(Attachment.build("logo.png", "image/png", BINARY, "logo1"))
  out = m.render
  assert out.include?("Content-Type: multipart/related; boundary=\"B_rel\"\r\n")
  assert out.include?("Content-Disposition: inline; filename=\"logo.png\"\r\n")
  assert out.include?("Content-ID: <logo1>\r\n")
  assert !out.include?("multipart/mixed")
end

test "inline and ordinary attachments together nest related inside mixed" do
  m = build
  m.html_body = "<img src=\"cid:logo1\">"
  m.attach(Attachment.build("logo.png", "image/png", BINARY, "logo1"))
  m.attach(Attachment.build("invoice.pdf", "application/pdf", "pdf"))
  out = m.render
  assert out.index("multipart/mixed") < out.index("multipart/related")
  assert out.index("multipart/related") < out.index("multipart/alternative")
  assert out.include?("Content-Disposition: attachment; filename=\"invoice.pdf\"\r\n")
end

test "an inline part without an HTML body is sent as an ordinary attachment" do
  m = build
  m.attach(Attachment.build("logo.png", "image/png", BINARY, "logo1"))
  out = m.render
  assert out.include?("multipart/mixed")
  assert !out.include?("multipart/related")
end

test "a Japanese filename is carried in both parameters" do
  m = build
  m.attach(Attachment.build("請求書.pdf", "application/pdf", "pdf"))
  out = m.render
  assert out.include?("name=\"___.pdf\"; name*=UTF-8''%E8%AB%8B%E6%B1%82%E6%9B%B8.pdf")
  assert out.include?("filename*=UTF-8''%E8%AB%8B%E6%B1%82%E6%9B%B8.pdf")
end

test "rendering without attachments is unchanged" do
  m = build
  assert !m.render.include?("multipart")
end

PostalTest.run!
