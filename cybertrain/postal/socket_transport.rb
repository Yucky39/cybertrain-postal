require "socket"
require "openssl"
require "cybertrain/postal/errors"
require "cybertrain/postal/transport"

module Cybertrain
  module Postal
    # A Transport over a TCP socket, with TLS through the openssl package that
    # ships with Spinel (docs/m0-findings.md). Not required by
    # "cybertrain/postal" itself: programs that only need messages and
    # ScriptedTransport do not have to link libssl. Use
    #   require "cybertrain/postal/socket_transport"
    #
    # implicit_tls is true for port 465 (TLS from the first byte); otherwise the
    # Session upgrades with STARTTLS. verify_cert false turns certificate
    # checking off and exists for local test servers only.
    #
    # Every read waits with wait_readable(timeout) first (spikes/NOTES.md rule 20).
    class SocketTransport < Transport
      MAX_LINE = 65536

      def initialize(host, port, implicit_tls, timeout, verify_cert)
        @host = host
        @timeout = timeout
        @verify_cert = verify_cert
        @buf = +""
        @tls = false
        @ssl = nil
        @sock = open_socket(host, port)
        raise InsecureConnection, "TLS handshake failed" if implicit_tls && !start_tls
      end

      def read_line
        loop do
          at = @buf.byteindex("\n")
          unless at.nil?
            line = @buf.byteslice(0, at)
            @buf = @buf.byteslice(at + 1, @buf.bytesize - at - 1)
            line = line.byteslice(0, line.bytesize - 1) if line.end_with?("\r")
            return line
          end
          return nil if @buf.bytesize > MAX_LINE
          chunk = read_chunk
          return nil if chunk.nil?
          @buf << chunk
        end
      end

      def write(data)
        if @tls
          sent = 0
          total = data.bytesize
          while sent < total
            sent += @ssl.syswrite(data.byteslice(sent, total - sent))
          end
        else
          @sock.write(data)
        end
        nil
      end

      def close
        if @tls
          @ssl.sysclose
        else
          @sock.close
        end
        nil
      end

      def secure?
        @tls
      end

      def loopback?
        @host == "127.0.0.1" || @host == "::1" || @host == "localhost"
      end

      # False when the handshake fails, or when the server sent bytes after its
      # 220 reply before the handshake (a STARTTLS injection attempt).
      def start_tls
        return false if @buf.bytesize > 0
        ctx = OpenSSL::SSL::SSLContext.new
        ctx.verify_mode = OpenSSL::SSL::VERIFY_NONE unless @verify_cert
        ssl = OpenSSL::SSL::SSLSocket.new(@sock, ctx)
        ssl.hostname = @host
        begin
          ssl.connect
        rescue OpenSSL::SSL::SSLError, StandardError
          return false
        end
        @ssl = ssl
        @tls = true
        true
      end

      private

      def open_socket(host, port)
        TCPSocket.new(host, port)
      rescue SystemCallError, SocketError
        raise ConnectionLost, "cannot connect to " + host
      end

      # Bytes from the stream, or nil at end of stream / timeout.
      def read_chunk
        if @tls
          return @ssl.sysread(4096) if @ssl.pending > 0
          return nil if @sock.wait_readable(@timeout).nil?
          begin
            @ssl.sysread(4096)
          rescue EOFError, SystemCallError, OpenSSL::SSL::SSLError
            nil
          end
        else
          return nil if @sock.wait_readable(@timeout).nil?
          begin
            @sock.readpartial(4096)
          rescue EOFError, SystemCallError
            nil
          end
        end
      end
    end
  end
end
