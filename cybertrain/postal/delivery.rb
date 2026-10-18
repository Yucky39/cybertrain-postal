require "cybertrain/postal/errors"
require "cybertrain/postal/message"
require "cybertrain/postal/result"
require "cybertrain/postal/session"
require "cybertrain/postal/transport"

module Cybertrain
  module Postal
    # The entry point applications use. deliver returns a Result (inspect
    # ok? / temporary? / permanent? to decide on a retry); deliver! raises
    # DeliveryFailed instead. Subclasses implement perform.
    class Delivery
      def deliver(message)
        perform(message)
      end

      def deliver!(message)
        result = perform(message)
        raise DeliveryFailed, result.code.to_s + " " + result.text unless result.ok?
        result
      end

      # Runs the delivery on its own thread and answers a DeliveryJob at once.
      # Whatever perform raises ends up in the job as a failed Result (code 0),
      # never in the caller. Use a Delivery that can serve concurrent calls
      # (RetryingDelivery builds a fresh transport per attempt).
      def deliver_later(message)
        job = DeliveryJob.new
        start_job(job, message)
        job
      end

      # Abstract hook (spikes/NOTES.md rule 3).
      def perform(message)
        Result.new(false, 0, "perform is not implemented", [""].clear, [""].clear)
      end

      def start_job(job, message)
        Thread.new { run_job(job, message) }
        nil
      end

      def run_job(job, message)
        begin
          job.finish(perform(message))
        rescue PostalError
          job.finish(Result.new(false, 0, "delivery raised an error", [""].clear, [""].clear))
        rescue StandardError
          job.finish(Result.new(false, 0, "delivery raised an unexpected error", [""].clear, [""].clear))
        end
        nil
      end
    end

    # The handle deliver_later returns.
    class DeliveryJob
      def initialize
        @done = false
        @result = Result.new(false, 0, "pending", [""].clear, [""].clear)
      end

      def finish(result)
        @result = result
        @done = true
        nil
      end

      def done?
        @done
      end

      # Blocks (yielding to other threads) until the delivery has finished.
      def wait
        sleep(0.005) until @done
        @result
      end
    end

    # Sends through one SMTP Session. The transport is used up by one
    # delivery; a connection factory for repeated sends arrives with the
    # socket transports (M2).
    class SmtpDelivery < Delivery
      def initialize(transport, local_hostname, username, password, require_tls)
        @transport = transport
        @local_hostname = local_hostname
        @username = username
        @password = password
        @require_tls = require_tls
      end

      def perform(message)
        Session.new(@transport, @local_hostname, @require_tls).deliver(message, @username, @password)
      end
    end

    # Development delivery: writes one line per message and sends nothing.
    # Recipients, subject, body and credentials are never logged.
    class LogDelivery < Delivery
      attr_reader :lines

      def initialize(echo)
        @echo = echo
        @lines = [""]
        @lines.clear
      end

      def perform(message)
        rcpts = message.recipient_addrs
        line = "mail logged: recipients=" + rcpts.length.to_s + " bytes=" + message.render.bytesize.to_s
        @lines << line
        puts line if @echo
        Result.new(true, 250, "logged", rcpts, [""].clear)
      end
    end

    # Test delivery: keeps every message it is given and sends nothing.
    class TestDelivery < Delivery
      attr_reader :messages

      def initialize
        @messages = Array.new(0) { Message.new(Address.build("seed@example.com", "")) }
      end

      def perform(message)
        @messages << message
        Result.new(true, 250, "recorded", message.recipient_addrs, [""].clear)
      end

      def clear
        @messages.clear
        nil
      end
    end
  end
end
