# Errors raised by Cybertrain::Postal. Under Spinel an exception's class
# hierarchy is invisible (spikes/NOTES.md rules 47, 54), so callers tell them
# apart with one rescue clause per class, never with is_a?.
module Cybertrain
  module Postal
    class PostalError < StandardError
    end

    # The message or an address cannot be sent as given (header injection,
    # malformed address).
    class InvalidMessage < PostalError
    end

    # The server's replies do not follow RFC 5321.
    class ProtocolError < PostalError
    end

    # The connection ended or timed out before a complete reply.
    class ConnectionLost < PostalError
    end

    # Refused to continue without TLS, or TLS could not be established.
    class InsecureConnection < PostalError
    end
  end
end
