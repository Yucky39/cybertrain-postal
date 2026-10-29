module Cybertrain
  module Postal
    # What a Session talks through. Subclasses: ScriptedTransport (tests) and,
    # in later milestones, the socket transports. The base declares every hook
    # a subclass fills in (spikes/NOTES.md rule 3).
    class Transport
      # One line without its CRLF, or nil at end of stream / timeout.
      def read_line
        nil
      end

      def write(data)
        nil
      end

      def close
        nil
      end

      # True while the stream is encrypted.
      def secure?
        false
      end

      # True for a connection that never leaves the machine (loopback, unix).
      def loopback?
        false
      end

      # Upgrades the stream to TLS after STARTTLS; false when impossible.
      def start_tls
        false
      end

      # Why the last start_tls returned false ("" when it did not or is not known).
      def tls_failure
        ""
      end
    end
  end
end
