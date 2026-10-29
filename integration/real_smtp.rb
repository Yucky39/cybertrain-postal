# Sends ONE test message through a real SMTP server and reports what happened.
# Run via script/check-real-smtp; read docs/real-smtp.md first.
#
# Settings (environment). The password is only read, never printed:
#
#   POSTAL_SMTP_HOST       required
#   POSTAL_SMTP_PORT       587 by default
#   POSTAL_SMTP_TLS        starttls (default; required, never downgraded) | implicit (port 465)
#   POSTAL_SMTP_USER       optional; with POSTAL_SMTP_PASSWORD
#   POSTAL_SMTP_PASSWORD
#   POSTAL_SMTP_AUTH       "" (PLAIN or LOGIN, whatever the server offers) | XOAUTH2
#                          (then POSTAL_SMTP_PASSWORD is the access token)
#   POSTAL_MAIL_FROM       required, the sender address
#   POSTAL_MAIL_TO         required, where the test message goes
#
# Certificate and host-name checks stay on: a server whose certificate does not
# verify is reported as a failure, not worked around.
require "cybertrain/postal"
require "cybertrain/postal/smtp_factory"

include Cybertrain::Postal

def setting(name, fallback)
  v = ENV[name]
  v.nil? || v.empty? ? fallback : v
end

host = setting("POSTAL_SMTP_HOST", "")
from = setting("POSTAL_MAIL_FROM", "")
to = setting("POSTAL_MAIL_TO", "")
if host.empty? || from.empty? || to.empty?
  puts "set POSTAL_SMTP_HOST, POSTAL_MAIL_FROM and POSTAL_MAIL_TO (see integration/real_smtp.rb)"
  exit(2)
end
port = setting("POSTAL_SMTP_PORT", "587").to_i
implicit = setting("POSTAL_SMTP_TLS", "starttls") == "implicit"
user = setting("POSTAL_SMTP_USER", "")
mech = setting("POSTAL_SMTP_AUTH", "")

m = Message.new(Address.build(from, "cybertrain-postal check"))
m.add_to(Address.build(to, ""))
m.subject = "cybertrain-postal: test message 日本語"
m.text_body = "This message was sent by integration/real_smtp.rb.\r\n日本語の本文。\r\n.この行は先頭がドットです。\r\n"

factory = SmtpDeliveryFactory.new(host, port, implicit, setting("POSTAL_HELO", "localhost"))
factory.credentials(user, setting("POSTAL_SMTP_PASSWORD", "")) unless user.empty?
factory.auth_mechanism = mech unless mech.empty?
factory.timeout = 20
factory.connect_timeout = 10

puts "server:  #{host}:#{port} (#{implicit ? 'implicit TLS' : 'STARTTLS required'}, certificate checks on)"
puts "auth:    #{user.empty? ? 'none' : (mech.empty? ? 'PLAIN/LOGIN' : mech) + ' as ' + user}"
begin
  r = factory.new_delivery.deliver(m)
  puts "result:  ok=#{r.ok?} code=#{r.code} #{r.text}"
  puts "refused: #{r.rejected.join(', ')}" unless r.rejected.empty?
  exit(r.ok? ? 0 : 1)
rescue InsecureConnection => e
  puts "result:  refused to continue: #{e.message}"
  exit(1)
rescue ConnectionLost => e
  puts "result:  connection failed: #{e.message}"
  exit(1)
rescue PostalError => e
  puts "result:  #{e.class.name}: #{e.message}"
  exit(1)
end
