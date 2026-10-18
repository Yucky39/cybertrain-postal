require "base64"
require "cybertrain/postal/errors"

module Cybertrain
  module Postal
    # Header and body encoding helpers (RFC 2047, RFC 2045 base64).
    module Mime
      # Largest byte count of one RFC 2047 encoded-word payload: 45 bytes
      # become 60 base64 characters, so "=?UTF-8?B?" + 60 + "?=" is 72 <= 75.
      WORD_BYTES = 45

      # Raises InvalidMessage when a header value holds CR, LF or NUL.
      def self.check_header_value(value)
        i = 0
        n = value.bytesize
        while i < n
          b = value.getbyte(i)
          if b == 13 || b == 10 || b == 0
            raise InvalidMessage, "header value contains a control character"
          end
          i += 1
        end
        value
      end

      # True when every byte is printable ASCII (space included).
      def self.plain_ascii?(text)
        i = 0
        n = text.bytesize
        while i < n
          b = text.getbyte(i)
          return false if b < 32 || b > 126
          i += 1
        end
        true
      end

      # Header text (a subject, a display name): printable ASCII passes
      # through, anything else becomes one or more RFC 2047 encoded-words,
      # split on UTF-8 character boundaries and folded with CRLF + space.
      def self.encode_text(text)
        check_header_value(text)
        return text if plain_ascii?(text)

        words = []
        bytes = text.bytesize
        pos = 0
        while pos < bytes
          len = WORD_BYTES
          if pos + len >= bytes
            len = bytes - pos
          else
            # step back so the cut does not fall inside a multibyte character
            while len > 1 && (text.getbyte(pos + len) & 0xC0) == 0x80
              len -= 1
            end
          end
          chunk = text.byteslice(pos, len)
          words << ("=?UTF-8?B?" + Base64.strict_encode64(chunk) + "?=")
          pos += len
        end
        words.join("\r\n ")
      end

      # RFC 5322 display-name: a quoted-string when ASCII specials need it,
      # an encoded-word when non-ASCII.
      def self.display_name(name)
        return "" if name.bytesize == 0
        return encode_text(name) unless plain_ascii?(name)
        check_header_value(name)
        specials = "\"(),.:;<>@[\\]"
        i = 0
        while i < name.bytesize
          if specials.include?(name.byteslice(i, 1))
            escaped = name.gsub("\\", "\\\\\\\\").gsub("\"", "\\\\\"")
            return "\"" + escaped + "\""
          end
          i += 1
        end
        name
      end

      # Base64 of the text, wrapped at 76 characters, each line ending CRLF.
      def self.base64_body(text)
        encoded = Base64.strict_encode64(text)
        out = +""
        pos = 0
        n = encoded.bytesize
        while pos < n
          out << encoded.byteslice(pos, 76)
          out << "\r\n"
          pos += 76
        end
        out
      end

      # Line endings as CRLF, whatever the input used.
      def self.crlf(text)
        text.gsub("\r\n", "\n").gsub("\n", "\r\n")
      end
    end
  end
end
