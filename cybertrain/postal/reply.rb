require "cybertrain/postal/errors"

module Cybertrain
  module Postal
    # One SMTP reply, possibly multi-line ("250-..." then "250 ...").
    class Reply
      attr_reader :code, :lines

      def initialize
        @code = 0
        @lines = [""]
        @lines.clear
        @final = false
      end

      # Feeds one line (without CRLF). Returns true once the reply is complete.
      def add_line(line)
        raise ProtocolError, "reply line too short" if line.bytesize < 3
        code = 0
        i = 0
        while i < 3
          b = line.getbyte(i)
          raise ProtocolError, "reply does not start with a 3-digit code" if b < 48 || b > 57
          code = code * 10 + (b - 48)
          i += 1
        end
        raise ProtocolError, "reply code out of range" if code < 200 || code > 599
        if @lines.length > 0 && code != @code
          raise ProtocolError, "reply code changed within a multi-line reply"
        end
        sep = line.bytesize > 3 ? line.getbyte(3) : 32
        raise ProtocolError, "reply has no separator after the code" if sep != 32 && sep != 45
        @code = code
        @lines << (line.bytesize > 4 ? line.byteslice(4, line.bytesize - 4) : "")
        @final = (sep == 32)
        @final
      end

      def complete?
        @final
      end

      def positive?
        @code >= 200 && @code < 400
      end

      def text
        @lines.join(" ")
      end
    end
  end
end
