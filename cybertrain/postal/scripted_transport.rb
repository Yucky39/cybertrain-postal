require "cybertrain/postal/transport"

module Cybertrain
  module Postal
    # A Transport for tests: replies come from a script, writes are recorded.
    class ScriptedTransport < Transport
      attr_reader :sent
      attr_writer :tls_ok

      def initialize(script, secure, loopback)
        @script = script
        @index = 0
        @sent = +""
        @secure = secure
        @loopback = loopback
        @tls_ok = true
        @closed = false
      end

      def read_line
        return nil if @index >= @script.length
        line = @script[@index]
        @index += 1
        line
      end

      def write(data)
        @sent << data
        nil
      end

      def close
        @closed = true
        nil
      end

      def closed?
        @closed
      end

      def secure?
        @secure
      end

      def loopback?
        @loopback
      end

      def start_tls
        return false unless @tls_ok
        @secure = true
        true
      end
    end
  end
end
