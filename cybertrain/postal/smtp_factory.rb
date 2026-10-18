require "cybertrain/postal/delivery"
require "cybertrain/postal/retry"
require "cybertrain/postal/socket_transport"

module Cybertrain
  module Postal
    # Opens a new SocketTransport and SmtpDelivery for every attempt, so it can
    # sit under a RetryingDelivery. Require "cybertrain/postal/smtp_factory".
    #
    #   factory = SmtpDeliveryFactory.new("smtp.example.com", 587, false, "app.example.com")
    #   factory.credentials("user", "secret")
    #   mailer = RetryingDelivery.new(factory, RetryPolicy.new(5, 2.0, 60.0), SystemSleeper.new)
    #   mailer.deliver_later(message)
    class SmtpDeliveryFactory < DeliveryFactory
      attr_writer :connect_timeout, :timeout, :total_timeout, :verify_cert, :require_tls

      def initialize(host, port, implicit_tls, local_hostname)
        @host = host
        @port = port
        @implicit_tls = implicit_tls
        @local_hostname = local_hostname
        @username = ""
        @password = ""
        @connect_timeout = 10
        @timeout = 30
        @total_timeout = 120
        @verify_cert = true
        @require_tls = true
      end

      def credentials(username, password)
        @username = username
        @password = password
        nil
      end

      def new_delivery
        transport = SocketTransport.new(@host, @port, @implicit_tls, @connect_timeout, @timeout, @total_timeout, @verify_cert)
        SmtpDelivery.new(transport, @local_hostname, @username, @password, @require_tls)
      end
    end
  end
end
