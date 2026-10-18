require "base64"
require "cybertrain/postal/errors"
require "cybertrain/postal/reply"
require "cybertrain/postal/result"
require "cybertrain/postal/message"
require "cybertrain/postal/transport"

module Cybertrain
  module Postal
    # One SMTP dialogue (RFC 5321) over a Transport: greeting, EHLO,
    # STARTTLS, AUTH PLAIN, MAIL FROM, RCPT TO, DATA, QUIT.
    #
    # TLS policy: when the server offers STARTTLS the session upgrades, and a
    # failed upgrade raises InsecureConnection -- it never falls back to plain
    # text. require_tls also refuses a server that does not offer STARTTLS.
    # Credentials are only sent over an encrypted or loopback transport.
    class Session
      def initialize(transport, local_hostname, require_tls)
        @transport = transport
        @host = local_hostname
        @require_tls = require_tls
      end

      def deliver(message, username, password)
        body = message.render
        rcpts = message.recipient_addrs

        greeting = read_reply
        return failure(greeting) unless greeting.code == 220

        ehlo = command("EHLO " + @host)
        return failure(ehlo) unless ehlo.code == 250
        caps = ehlo.lines

        unless @transport.secure?
          if offers?(caps, "STARTTLS")
            started = command("STARTTLS")
            return failure(started) unless started.code == 220
            raise InsecureConnection, "TLS could not be established" unless @transport.start_tls
            ehlo = command("EHLO " + @host)
            return failure(ehlo) unless ehlo.code == 250
            caps = ehlo.lines
          elsif @require_tls
            raise InsecureConnection, "server does not offer STARTTLS"
          end
        end

        if username.bytesize > 0
          unless @transport.secure? || @transport.loopback?
            raise InsecureConnection, "refusing to send credentials without TLS"
          end
          return failure_text(504, "server offers no AUTH PLAIN") unless offers_auth_plain?(caps)
          token = Base64.strict_encode64("\0" + username + "\0" + password)
          auth = command("AUTH PLAIN " + token)
          return failure(auth) unless auth.code == 235
        end

        from = command("MAIL FROM:<" + message.from.addr + ">")
        return failure(from) unless from.code == 250

        accepted = [""]
        accepted.clear
        rejected = [""]
        rejected.clear
        last = from
        rcpts.each do |addr|
          r = command("RCPT TO:<" + addr + ">")
          if r.code == 250 || r.code == 251
            accepted << addr
          else
            rejected << addr
            last = r
          end
        end
        if accepted.empty?
          command("RSET")
          quit
          return Result.new(false, last.code, last.text, accepted, rejected)
        end

        data = command("DATA")
        return failure(data) unless data.code == 354
        @transport.write(Session.dot_stuff(body))
        @transport.write(".\r\n")
        done = read_reply
        quit
        Result.new(done.code == 250, done.code, done.text, accepted, rejected)
      end

      # Doubles a leading "." on every line and makes sure the data ends
      # with CRLF (RFC 5321 4.5.2).
      def self.dot_stuff(data)
        text = data.end_with?("\r\n") ? data : data + "\r\n"
        text = "." + text if text.getbyte(0) == 46
        text.gsub("\r\n.", "\r\n..")
      end

      private

      def command(line)
        @transport.write(line + "\r\n")
        read_reply
      end

      def read_reply
        reply = Reply.new
        loop do
          line = @transport.read_line
          raise ConnectionLost, "connection closed before a complete reply" if line.nil?
          break if reply.add_line(line)
        end
        reply
      end

      def quit
        @transport.write("QUIT\r\n")
        @transport.read_line
        @transport.close
        nil
      end

      def failure(reply)
        quit
        Result.new(false, reply.code, reply.text, [""].clear, [""].clear)
      end

      def failure_text(code, text)
        quit
        Result.new(false, code, text, [""].clear, [""].clear)
      end

      def offers?(caps, keyword)
        caps.each do |line|
          return true if line.upcase == keyword
        end
        false
      end

      def offers_auth_plain?(caps)
        caps.each do |line|
          up = line.upcase
          next unless up.start_with?("AUTH ") || up.start_with?("AUTH=")
          return true if up.include?("PLAIN")
        end
        false
      end
    end
  end
end
