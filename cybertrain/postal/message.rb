require "securerandom"
require "cybertrain/postal/errors"
require "cybertrain/postal/mime"
require "cybertrain/postal/address"

module Cybertrain
  module Postal
    # An outgoing message. Date, Message-ID and the multipart boundary are
    # plain fields (set them for a byte-for-byte reproducible rendering; the
    # defaults come from Message.fresh_*).
    class Message
      attr_accessor :from, :subject, :text_body, :html_body, :date, :message_id, :boundary
      attr_reader :to, :cc, :bcc

      def initialize(from)
        @from = from
        @to = [from]
        @to.clear
        @cc = [from]
        @cc.clear
        @bcc = [from]
        @bcc.clear
        @subject = ""
        @text_body = ""
        @html_body = ""
        @date = ""
        @message_id = ""
        @boundary = ""
      end

      def add_to(address)
        @to << address
        nil
      end

      def add_cc(address)
        @cc << address
        nil
      end

      def add_bcc(address)
        @bcc << address
        nil
      end

      # Envelope recipients: to, cc and bcc (bcc never reaches a header).
      def recipient_addrs
        out = [""]
        out.clear
        @to.each { |a| out << a.addr }
        @cc.each { |a| out << a.addr }
        @bcc.each { |a| out << a.addr }
        out
      end

      def self.fresh_date
        Time.now.utc.strftime("%a, %d %b %Y %H:%M:%S +0000")
      end

      def self.fresh_token
        SecureRandom.hex(16)
      end

      # RFC 5322 text, CRLF line endings, 7-bit clean (bodies are base64).
      def render
        raise InvalidMessage, "message has no recipient" if recipient_addrs.empty?
        date = @date.bytesize == 0 ? Message.fresh_date : @date
        mid = @message_id.bytesize == 0 ? Message.fresh_token + "@" + domain_of(@from.addr) : @message_id
        Mime.check_header_value(date)
        Mime.check_header_value(mid)

        out = +""
        out << "Date: " << date << "\r\n"
        out << "From: " << @from.to_header << "\r\n"
        out << "To: " << join_addresses(@to) << "\r\n" if @to.length > 0
        out << "Cc: " << join_addresses(@cc) << "\r\n" if @cc.length > 0
        out << "Subject: " << Mime.encode_text(@subject) << "\r\n"
        out << "Message-ID: <" << mid << ">\r\n"
        out << "MIME-Version: 1.0\r\n"
        if @html_body.bytesize == 0
          out << "Content-Type: text/plain; charset=UTF-8\r\n"
          out << "Content-Transfer-Encoding: base64\r\n\r\n"
          out << Mime.base64_body(Mime.crlf(@text_body))
        else
          boundary = @boundary.bytesize == 0 ? "=_postal_" + Message.fresh_token : @boundary
          Mime.check_header_value(boundary)
          out << "Content-Type: multipart/alternative; boundary=\"" << boundary << "\"\r\n\r\n"
          out << "--" << boundary << "\r\n"
          out << "Content-Type: text/plain; charset=UTF-8\r\nContent-Transfer-Encoding: base64\r\n\r\n"
          out << Mime.base64_body(Mime.crlf(@text_body))
          out << "--" << boundary << "\r\n"
          out << "Content-Type: text/html; charset=UTF-8\r\nContent-Transfer-Encoding: base64\r\n\r\n"
          out << Mime.base64_body(Mime.crlf(@html_body))
          out << "--" << boundary << "--\r\n"
        end
        out
      end

      private

      def join_addresses(list)
        parts = [""]
        parts.clear
        list.each { |a| parts << a.to_header }
        parts.join(",\r\n ")
      end

      def domain_of(addr)
        at = addr.index("@")
        addr.byteslice(at + 1, addr.bytesize - at - 1)
      end
    end
  end
end
