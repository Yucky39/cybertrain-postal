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
    # Every read waits with wait_readable first (spikes/NOTES.md rule 20).
    # Three limits, all in seconds (0 or less means no limit):
    #   connect_timeout  opening the TCP connection (IPv4 hosts; an IPv6 literal
    #                    uses a plain blocking connect)
    #   timeout          one wait for the server to send something
    #   total_timeout    the whole dialogue, from construction to close
    # A transport serves one delivery.
    class SocketTransport < Transport
      MAX_LINE = 65536

      def initialize(host, port, implicit_tls, connect_timeout, timeout, total_timeout, verify_cert)
        @host = host
        @timeout = timeout
        @deadline = total_timeout > 0 ? SocketTransport.now + total_timeout : 0.0
        @verify_cert = verify_cert
        @buf = +""
        @tls = false
        @tls_failure = ""
        @ssl = nil
        @sock = open_socket(host, port, connect_timeout)
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

      def tls_failure
        @tls_failure
      end

      # False when the handshake fails or does not finish in time, or when the
      # server sent bytes after its 220 reply before the handshake (a STARTTLS
      # injection attempt). tls_failure says which.
      def start_tls
        @tls_failure = ""
        if @buf.bytesize > 0
          @tls_failure = "the server sent data before the handshake"
          return false
        end
        ctx = OpenSSL::SSL::SSLContext.new
        # Set both sides explicitly: the certificate must chain to a trusted CA
        # and name the host we connected to. Spinel's SSLContext happens to
        # start out that way; CRuby's does not, so no default is relied on.
        if @verify_cert
          ctx.verify_mode = OpenSSL::SSL::VERIFY_PEER
          ctx.verify_hostname = true
        else
          ctx.verify_mode = OpenSSL::SSL::VERIFY_NONE
          ctx.verify_hostname = false
        end
        ssl = OpenSSL::SSL::SSLSocket.new(@sock, ctx)
        ssl.hostname = @host
        begin
          # One handshake step at a time, so the timeouts apply: ssl.connect would
          # wait for a silent server for as long as it likes.
          loop do
            step = ssl.connect_nonblock(exception: false)
            if step == :wait_readable
              ready = readable?
            elsif step == :wait_writable
              ready = writable?
            else
              break
            end
            unless ready
              @tls_failure = "the handshake timed out (the server sent nothing; see docs/real-smtp.md)"
              return false
            end
          end
        rescue OpenSSL::SSL::SSLError, StandardError
          @tls_failure = "the handshake failed (certificate or host name not accepted, or no common protocol)"
          return false
        end
        @ssl = ssl
        @tls = true
        true
      end

      private

      def open_socket(host, port, limit)
        return TCPSocket.new(host, port) if limit <= 0 || host.include?(":")
        s = Socket.new(Socket::AF_INET, Socket::SOCK_STREAM, 0)
        addr = Socket.sockaddr_in(port, host)
        begin
          s.connect_nonblock(addr)
        rescue IO::WaitWritable
          if IO.select(nil, [s], nil, limit).nil?
            s.close
            raise ConnectionLost, "connect to " + host + " timed out"
          end
          begin
            s.connect_nonblock(addr)
          rescue Errno::EISCONN
            # connected: the wait above is what completed it
          end
          # A refused connect also makes the socket writable, and some kernels
          # then report nothing from a second connect: ask for the error.
          if s.getsockopt(Socket::SOL_SOCKET, Socket::SO_ERROR).int != 0
            s.close
            raise ConnectionLost, "cannot connect to " + host
          end
        end
        s
      rescue SystemCallError, SocketError
        raise ConnectionLost, "cannot connect to " + host
      end

      def self.now
        Process.clock_gettime(Process::CLOCK_MONOTONIC)
      end

      # How long the next wait may last: the per-wait limit, cut short by the
      # overall deadline. 0.0 means the deadline has passed; -1.0 no limit.
      def wait_limit
        left = -1.0
        if @deadline > 0.0
          left = @deadline - SocketTransport.now
          return 0.0 if left <= 0.0
        end
        return left if @timeout <= 0
        return @timeout if left < 0.0 || @timeout < left
        left
      end

      def writable?
        limit = wait_limit
        return false if limit == 0.0
        return !@sock.wait_writable(limit).nil? if limit > 0.0
        !@sock.wait_writable.nil?
      end

      def readable?
        limit = wait_limit
        return false if limit == 0.0
        return !@sock.wait_readable(limit).nil? if limit > 0.0
        !@sock.wait_readable.nil?
      end

      # Bytes from the stream, or nil at end of stream / timeout.
      def read_chunk
        if @tls
          return @ssl.sysread(4096) if @ssl.pending > 0
          return nil unless readable?
          begin
            @ssl.sysread(4096)
          rescue EOFError, SystemCallError, OpenSSL::SSL::SSLError
            nil
          end
        else
          return nil unless readable?
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
