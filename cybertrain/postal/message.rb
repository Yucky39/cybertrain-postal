require "securerandom"
require "cybertrain/postal/errors"
require "cybertrain/postal/mime"
require "cybertrain/postal/address"
require "cybertrain/postal/attachment"

module Cybertrain
  module Postal
    # An outgoing message. Date, Message-ID and the multipart boundary are
    # plain fields (set them for a byte-for-byte reproducible rendering; the
    # defaults come from Message.fresh_*).
    class Message
      attr_accessor :from, :subject, :text_body, :html_body, :date, :message_id, :boundary
      attr_reader :to, :cc, :bcc, :attachments

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
        @attachments = Array.new(0) { Attachment.new("", "", "", "") }
      end

      def attach(attachment)
        @attachments << attachment
        nil
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
        base = @boundary.bytesize == 0 ? "=_postal_" + Message.fresh_token : @boundary
        Mime.check_header_value(base)
        out << body_entity(base)
        out
      end

      private

      def text_entity
        "Content-Type: text/plain; charset=UTF-8\r\nContent-Transfer-Encoding: base64\r\n\r\n" +
          Mime.base64_body(Mime.crlf(@text_body))
      end

      def html_entity
        "Content-Type: text/html; charset=UTF-8\r\nContent-Transfer-Encoding: base64\r\n\r\n" +
          Mime.base64_body(Mime.crlf(@html_body))
      end

      def alternative_entity(boundary)
        out = +""
        out << "Content-Type: multipart/alternative; boundary=\"" << boundary << "\"\r\n\r\n"
        out << "--" << boundary << "\r\n" << text_entity
        out << "--" << boundary << "\r\n" << html_entity
        out << "--" << boundary << "--\r\n"
        out
      end

      def attachment_entity(att)
        disposition = att.inline? ? "inline" : "attachment"
        out = +""
        out << "Content-Type: " << att.content_type << "; " << Mime.param("name", att.filename) << "\r\n"
        out << "Content-Transfer-Encoding: base64\r\n"
        out << "Content-Disposition: " << disposition << "; " << Mime.param("filename", att.filename) << "\r\n"
        out << "Content-ID: <" << att.content_id << ">\r\n" if att.inline?
        out << "\r\n"
        out << Mime.base64_body(att.data)
        out
      end

      # The message body as a MIME entity (its own Content-Type header
      # included). Structure, outermost first:
      #   multipart/mixed       when there are ordinary attachments
      #   multipart/related     when inline parts accompany an HTML body
      #   multipart/alternative when there is an HTML body next to the text
      def body_entity(base)
        inline = [@attachments[0]]
        inline.clear
        regular = [@attachments[0]]
        regular.clear
        @attachments.each do |att|
          if att.inline? && @html_body.bytesize > 0
            inline << att
          else
            regular << att
          end
        end

        core = +""
        if @html_body.bytesize == 0
          core << text_entity
        elsif inline.empty?
          core << alternative_entity(base)
        else
          rel = base + "_rel"
          core << "Content-Type: multipart/related; boundary=\"" << rel << "\"\r\n\r\n"
          core << "--" << rel << "\r\n" << alternative_entity(base)
          inline.each { |att| core << "--" << rel << "\r\n" << attachment_entity(att) }
          core << "--" << rel << "--\r\n"
        end
        return core if regular.empty?

        mix = base + "_mix"
        out = +""
        out << "Content-Type: multipart/mixed; boundary=\"" << mix << "\"\r\n\r\n"
        out << "--" << mix << "\r\n" << core
        regular.each { |att| out << "--" << mix << "\r\n" << attachment_entity(att) }
        out << "--" << mix << "--\r\n"
        out
      end

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
