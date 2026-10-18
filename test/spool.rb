require_relative "support/harness"
require "tmpdir"
require "cybertrain/postal"

include Cybertrain::Postal

def message(subject)
  m = Message.new(Address.build("noreply@example.com", ""))
  m.add_to(Address.build("taro@example.com", ""))
  m.add_bcc(Address.build("audit@example.com", ""))
  m.subject = subject
  m.text_body = "本文"
  m.date = "Sun, 18 Oct 2026 10:00:00 +0000"
  m.message_id = "id@example.com"
  m
end

# Answers scripted codes in order (250 = success) and keeps what it was given.
class ScriptedDelivery < Delivery
  attr_reader :sent, :calls

  def initialize(codes)
    @codes = codes
    @calls = 0
    @sent = [""]
    @sent.clear
  end

  def perform(message)
    code = @codes[@calls < @codes.length ? @calls : @codes.length - 1]
    @calls += 1
    @sent << message.render
    raise ConnectionLost, "scripted" if code == 0
    return Result.new(true, 250, "queued", [""].clear, [""].clear) if code == 250
    Result.new(false, code, "scripted", [""].clear, [""].clear)
  end
end

class ScriptedFactory < DeliveryFactory
  def initialize(delivery)
    @delivery = delivery
  end

  def new_delivery
    @delivery
  end
end

def fresh_spool
  Spool.new(Dir.mktmpdir("postal-spool"))
end

def runner(spool, codes, attempts)
  d = ScriptedDelivery.new(codes)
  [SpoolRunner.new(spool, ScriptedFactory.new(d), RetryPolicy.new(attempts, 10.0, 60.0)), d]
end

test "enqueue stores the message and the runner delivers it once" do
  spool = fresh_spool
  id = spool.enqueue(message("Hi"), 1000)
  assert_equal 1, spool.count("new")
  run, d = runner(spool, [250], 3)
  report = run.run_once(1000)
  assert_equal 1, report.delivered
  assert_equal 0, spool.count("new")
  assert_equal 0, spool.count("active")
  assert_equal 1, d.calls
  assert_equal message("Hi").render, d.sent[0]
end

test "bcc recipients stay in the envelope but out of the headers" do
  spool = fresh_spool
  id = spool.enqueue(message("Hi"), 1000)
  item = spool.peek("new", id)
  assert_equal ["taro@example.com", "audit@example.com"], item.recipients
  assert !item.data.include?("audit@example.com")
end

test "a temporary failure is rescheduled with backoff" do
  spool = fresh_spool
  id = spool.enqueue(message("Hi"), 1000)
  run, d = runner(spool, [451, 250], 5)
  report = run.run_once(1000)
  assert_equal 1, report.deferred
  item = spool.peek("new", id)
  assert_equal 1, item.attempts
  assert_equal 1010, item.next_at
  assert_equal "451 scripted", item.last_error
  assert_equal 0, run.run_once(1005).delivered
  assert_equal 1, d.calls
  assert_equal 1, run.run_once(1010).delivered
  assert_equal 0, spool.count("new")
end

test "a lost connection counts as temporary" do
  spool = fresh_spool
  id = spool.enqueue(message("Hi"), 1000)
  run, d = runner(spool, [0], 5)
  assert_equal 1, run.run_once(1000).deferred
  assert_equal "421 connection lost", spool.peek("new", id).last_error
end

test "a permanent failure moves to failed at once" do
  spool = fresh_spool
  id = spool.enqueue(message("Hi"), 1000)
  run, d = runner(spool, [550], 5)
  assert_equal 1, run.run_once(1000).failed
  assert_equal 0, spool.count("new")
  assert_equal 1, spool.count("failed")
  assert_equal "550 scripted", spool.peek("failed", id).last_error
end

test "the message is given up after max_attempts" do
  spool = fresh_spool
  spool.enqueue(message("Hi"), 1000)
  run, d = runner(spool, [451], 2)
  assert_equal 1, run.run_once(1000).deferred
  assert_equal 1, run.run_once(1010).failed
  assert_equal 2, d.calls
  assert_equal 1, spool.count("failed")
end

test "claim is exclusive" do
  spool = fresh_spool
  id = spool.enqueue(message("Hi"), 1000)
  first = spool.claim(id)
  second = spool.claim(id)
  assert first.valid?
  assert !second.valid?
end

test "stale claimed messages are put back" do
  spool = fresh_spool
  id = spool.enqueue(message("Hi"), 1000)
  spool.claim(id)
  assert_equal 1, spool.count("active")
  assert_equal 0, spool.recover_stale(Time.now.to_i, 3600)
  assert_equal 1, spool.recover_stale(Time.now.to_i + 7200, 3600)
  assert_equal 1, spool.count("new")
end

test "oldest messages are delivered first" do
  spool = fresh_spool
  spool.enqueue(message("second"), 2000)
  spool.enqueue(message("first"), 1000)
  run, d = runner(spool, [250], 3)
  run.run_once(3000)
  assert d.sent[0].include?("Subject: first")
  assert d.sent[1].include?("Subject: second")
  assert_equal 2, d.calls
end

test "QueueDelivery answers 250 queued and leaves the work to the runner" do
  spool = fresh_spool
  r = QueueDelivery.new(spool).deliver(message("Hi"))
  assert r.ok?
  assert r.text.start_with?("queued ")
  assert_equal 1, spool.count("new")
end

PostalTest.run!
