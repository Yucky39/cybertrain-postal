# M0: TLS via the bundled openssl package. Usage: m0_tls HOST PORT [noverify]
require "socket"
require "openssl"

host = ARGV[0]
port = ARGV[1].to_i
sock = TCPSocket.new(host, port)
ctx = OpenSSL::SSL::SSLContext.new
ctx.verify_mode = OpenSSL::SSL::VERIFY_NONE if ARGV[2] == "noverify"
ssl = OpenSSL::SSL::SSLSocket.new(sock, ctx)
ssl.hostname = host
ssl.connect
puts "connected"
r = sock.wait_readable(5)
puts "ready: #{r.nil? ? 'no' : 'yes'}"
puts ssl.sysread(4096).inspect
ssl.syswrite("QUIT\r\n")
ssl.sysclose
sock.close
puts "end"
