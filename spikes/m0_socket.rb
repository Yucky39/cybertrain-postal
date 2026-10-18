# M0: TCPSocket behaviour: wait_readable before readpartial, timeout, write.
require "socket"

srv = TCPServer.new("127.0.0.1", 0)
port = srv.addr[1]
cli = TCPSocket.new("127.0.0.1", port)
peer = srv.accept

r = cli.wait_readable(0.2)
puts "idle wait_readable: #{r.nil? ? 'nil' : 'ready'}"

peer.write("220 hello\r\n")
r = cli.wait_readable(1)
puts "after write wait_readable: #{r.nil? ? 'nil' : 'ready'}"
puts cli.readpartial(4096).inspect

cli.write("EHLO x\r\n")
r = peer.wait_readable(1)
puts "peer sees: #{peer.readpartial(4096).inspect}"

peer.close
r = cli.wait_readable(1)
begin
  cli.readpartial(4096)
rescue EOFError
  puts "eof"
end
cli.close
srv.close
puts "end"
