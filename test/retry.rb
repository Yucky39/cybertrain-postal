require_relative "support/harness"
require "cybertrain/postal"

include Cybertrain::Postal

def fail_result(code, text)
  Result.new(false, code, text, [""].clear, [""].clear)
end

def ok_result
  Result.new(true, 250, "queued", [""].clear, [""].clear)
end

# Answers scripted codes in order; 0 raises ConnectionLost, -1 raises InvalidMessage.
class ScriptedDelivery < Delivery
  attr_reader :calls

  def initialize(codes)
    @codes = codes
    @calls = 0
  end

  def perform(message)
    code = @codes[@calls < @codes.length ? @calls : @codes.length - 1]
    @calls += 1
    raise ConnectionLost, "scripted" if code == 0
    raise InvalidMessage, "scripted" if code == -1
    return ok_result if code == 250
    fail_result(code, "scripted")
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

class RecordingSleeper < Sleeper
  attr_reader :pauses

  def initialize
    @pauses = [1.5]
    @pauses.clear
  end

  def pause(seconds)
    @pauses << seconds
    nil
  end
end

def message
  m = Message.new(Address.build("a@example.com", ""))
  m.add_to(Address.build("b@example.com", ""))
  m.subject = "s"
  m.text_body = "t"
  m.date = "Sun, 18 Oct 2026 10:00:00 +0000"
  m.message_id = "id@example.com"
  m
end

def run(codes, attempts)
  d = ScriptedDelivery.new(codes)
  s = RecordingSleeper.new
  r = RetryingDelivery.new(ScriptedFactory.new(d), RetryPolicy.new(attempts, 1.0, 5.0), s)
  result = r.deliver(message)
  [result, d.calls, s.pauses]
end

test "the backoff doubles and is capped" do
  p = RetryPolicy.new(9, 1.0, 5.0)
  assert_equal [1.0, 2.0, 4.0, 5.0, 5.0], [p.delay_after(1), p.delay_after(2), p.delay_after(3), p.delay_after(4), p.delay_after(5)]
end

test "a temporary failure is retried until it succeeds" do
  result, calls, pauses = run([451, 451, 250], 5)
  assert result.ok?
  assert_equal 3, calls
  assert_equal [1.0, 2.0], pauses
end

test "a permanent failure is not retried" do
  result, calls, pauses = run([550, 250], 5)
  assert result.permanent?
  assert_equal 1, calls
  assert_equal 0, pauses.length
end

test "retries stop at max_attempts and answer the last failure" do
  result, calls, pauses = run([451], 3)
  assert result.temporary?
  assert_equal 3, calls
  assert_equal [1.0, 2.0], pauses
end

test "a lost connection is retried as a temporary failure" do
  result, calls, pauses = run([0, 250], 3)
  assert result.ok?
  assert_equal 2, calls
end

test "a lost connection that never recovers answers 421" do
  result, calls, pauses = run([0], 2)
  assert !result.ok?
  assert_equal 421, result.code
  assert_equal 2, calls
end

def invalid_run
  d = ScriptedDelivery.new([-1, 250])
  r = RetryingDelivery.new(ScriptedFactory.new(d), RetryPolicy.new(5, 1.0, 5.0), RecordingSleeper.new)
  begin
    r.deliver(message)
    "no raise"
  rescue InvalidMessage
    "raised " + d.calls.to_s
  end
end

test "an invalid message is raised at once, not retried" do
  assert_equal "raised 1", invalid_run
end

test "deliver_later answers a job that finishes with the Result" do
  d = TestDelivery.new
  job = d.deliver_later(message)
  result = job.wait
  assert job.done?
  assert result.ok?
  assert_equal 1, d.messages.length
end

test "an error inside deliver_later ends up in the job, not the caller" do
  job = ScriptedDelivery.new([-1]).deliver_later(message)
  result = job.wait
  assert !result.ok?
  assert_equal 0, result.code
end

test "several jobs run side by side" do
  d = TestDelivery.new
  jobs = [d.deliver_later(message), d.deliver_later(message), d.deliver_later(message)]
  jobs.each { |j| j.wait }
  assert_equal 3, d.messages.length
end

PostalTest.run!
