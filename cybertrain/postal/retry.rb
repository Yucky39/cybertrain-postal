require "cybertrain/postal/errors"
require "cybertrain/postal/result"
require "cybertrain/postal/delivery"

module Cybertrain
  module Postal
    # Exponential backoff: delay(n) = min(base_delay * 2**(n-1), max_delay)
    # seconds after the n-th failed attempt. No jitter, so tests are exact.
    class RetryPolicy
      attr_reader :max_attempts

      def initialize(max_attempts, base_delay, max_delay)
        @max_attempts = max_attempts
        @base_delay = base_delay
        @max_delay = max_delay
      end

      def delay_after(attempt)
        d = @base_delay
        i = 1
        while i < attempt && d < @max_delay
          d = d * 2
          i += 1
        end
        d > @max_delay ? @max_delay : d
      end

      # Only a temporary (4xx) failure is worth another attempt; a permanent
      # (5xx) one will fail again.
      def retry?(result)
        result.temporary?
      end
    end

    # Waits between attempts. The base class does not wait, which is what
    # tests want; SystemSleeper sleeps for real.
    class Sleeper
      def pause(seconds)
        nil
      end
    end

    class SystemSleeper < Sleeper
      def pause(seconds)
        sleep(seconds)
        nil
      end
    end

    # Builds a fresh Delivery for every attempt, because a transport serves
    # one delivery only. Subclasses override new_delivery.
    class DeliveryFactory
      def new_delivery
        Delivery.new
      end
    end

    # Retries temporary failures with backoff. A lost connection counts as a
    # temporary failure (code 421). InvalidMessage, InsecureConnection and
    # ProtocolError are not retried: they would fail the same way again.
    class RetryingDelivery < Delivery
      attr_reader :attempts

      def initialize(factory, policy, sleeper)
        @factory = factory
        @policy = policy
        @sleeper = sleeper
        @attempts = 0
      end

      def perform(message)
        @attempts = 0
        result = attempt(message)
        while @policy.retry?(result) && @attempts < @policy.max_attempts
          @sleeper.pause(@policy.delay_after(@attempts))
          result = attempt(message)
        end
        result
      end

      private

      def attempt(message)
        @attempts += 1
        begin
          @factory.new_delivery.deliver(message)
        rescue ConnectionLost
          Result.new(false, 421, "connection lost", [""].clear, [""].clear)
        end
      end
    end
  end
end
