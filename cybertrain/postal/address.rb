require "cybertrain/postal/errors"
require "cybertrain/postal/mime"

module Cybertrain
  module Postal
    # An envelope / header address: ASCII addr-spec plus an optional display
    # name. Non-ASCII addresses (SMTPUTF8) are refused.
    class Address
      FORBIDDEN = "<>(),;:\"[]\\"
      MAX_LENGTH = 254

      attr_reader :addr, :display_name

      def initialize(addr, display_name)
        @addr = addr
        @display_name = display_name
      end

      def self.build(addr, display_name = "")
        Address.check_addr(addr)
        Mime.check_header_value(display_name)
        Address.new(addr, display_name)
      end

      def self.check_addr(addr)
        n = addr.bytesize
        raise InvalidMessage, "address is empty or too long" if n == 0 || n > MAX_LENGTH
        at = -1
        i = 0
        while i < n
          b = addr.getbyte(i)
          raise InvalidMessage, "address has a control or non-ASCII byte" if b <= 32 || b >= 127
          raise InvalidMessage, "address has a forbidden character" if FORBIDDEN.include?(addr.byteslice(i, 1))
          if b == 64
            raise InvalidMessage, "address has more than one @" if at >= 0
            at = i
          end
          i += 1
        end
        raise InvalidMessage, "address needs a local part and a domain" if at < 1 || at == n - 1
        domain = addr.byteslice(at + 1, n - at - 1)
        if domain.getbyte(0) == 46 || domain.getbyte(domain.bytesize - 1) == 46 || domain.include?("..")
          raise InvalidMessage, "address has a malformed domain"
        end
        addr
      end

      # "Name <addr>" for a header, or the bare addr.
      def to_header
        name = Mime.display_name(@display_name)
        return @addr if name.bytesize == 0
        name + " <" + @addr + ">"
      end
    end
  end
end
