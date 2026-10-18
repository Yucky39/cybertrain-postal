require_relative "support/harness"
require "cybertrain/postal"
require "cybertrain/postal/socket_transport"

include Cybertrain::Postal

def clock
  Process.clock_gettime(Process::CLOCK_MONOTONIC)
end

def serve
  srv = TCPServer.new("127.0.0.1", 0)
  srv
end

test "read_line joins CRLF lines split across writes" do
  srv = serve
  t = SocketTransport.new("127.0.0.1", srv.addr[1], false, 2, 2, 0, false)
  peer = srv.accept
  peer.write("250-first\r\n250 sec")
  peer.write("ond\r\n")
  assert_equal "250-first", t.read_line
  assert_equal "250 second", t.read_line
  t.close
  peer.close
  srv.close
end

test "a silent server ends the wait after the per-wait timeout" do
  srv = serve
  t = SocketTransport.new("127.0.0.1", srv.addr[1], false, 2, 1, 0, false)
  peer = srv.accept
  started = clock
  assert t.read_line.nil?
  spent = clock - started
  assert spent >= 0.8
  assert spent < 3.0
  t.close
  peer.close
  srv.close
end

test "the overall deadline cuts a longer per-wait timeout short" do
  srv = serve
  t = SocketTransport.new("127.0.0.1", srv.addr[1], false, 2, 30, 1, false)
  peer = srv.accept
  started = clock
  assert t.read_line.nil?
  assert clock - started < 3.0
  t.close
  peer.close
  srv.close
end

test "a silent server makes Session raise ConnectionLost" do
  srv = serve
  t = SocketTransport.new("127.0.0.1", srv.addr[1], false, 2, 1, 0, false)
  peer = srv.accept
  m = Message.new(Address.build("a@example.com", ""))
  m.add_to(Address.build("b@example.com", ""))
  lost = false
  begin
    Session.new(t, "c", false).deliver(m, "", "")
  rescue ConnectionLost
    lost = true
  end
  assert lost
  peer.close
  srv.close
end

test "a refused connection raises ConnectionLost" do
  srv = serve
  port = srv.addr[1]
  srv.close
  lost = false
  begin
    SocketTransport.new("127.0.0.1", port, false, 2, 2, 0, false)
  rescue ConnectionLost
    lost = true
  end
  assert lost
end

test "an unreachable host fails within the connect timeout" do
  started = clock
  lost = false
  begin
    SocketTransport.new("192.0.2.1", 25, false, 1, 2, 0, false)
  rescue ConnectionLost
    lost = true
  end
  assert lost
  assert clock - started < 4.0
end

PostalTest.run!
