module Cybertrain
  module Postal
    # Outcome of one delivery attempt. A 4xx code is a temporary failure
    # (worth retrying), a 5xx a permanent one. code is 0 when no reply was
    # involved (for example no recipient was accepted).
    class Result
      attr_reader :ok, :code, :text, :accepted, :rejected

      def initialize(ok, code, text, accepted, rejected)
        @ok = ok
        @code = code
        @text = text
        @accepted = accepted
        @rejected = rejected
      end

      def ok?
        @ok
      end

      def temporary?
        !@ok && @code >= 400 && @code < 500
      end

      def permanent?
        !@ok && @code >= 500
      end
    end
  end
end
