# frozen_string_literal: true

require "json"
require_relative "server"
require_relative "stripe_cli"

module VcrStripeWebhook
  class EventReceiver
    class << self
      def instance
        @instance ||= EventReceiver.new
      end

      def terminate
        return unless @instance

        @instance.stop
        @instance = nil
      end
    end

    def initialize
      @started = false
    end

    def start
      return if @started

      api_key = VcrStripeWebhook.configuration.stripe_api_key

      @fence_mutex = Mutex.new
      @fence_cond_var = ConditionVariable.new
      @fence_test_clock_id = nil
      @fence_signaled = false
      @last_fence_event_created = nil

      @cassette = nil
      @server = VcrStripeWebhook::Server.new do |payload|
        receive_webhook(payload)
      end
      @cli = VcrStripeWebhook::StripeCLI.new(@server.port, api_key)
      @started = true
    end

    def stop
      @cli.terminate
      @server.close
      @started = false
    end

    def use_cassete(cassette)
      if cassette.recording?
        start
        logger.info "Using cassette: #{cassette.name}"
        @cassette = cassette
        yield cassette.vcr_cassette
        logger.info "Eject cassette: #{cassette.name}"
        @cassette = nil
        wait_for_rest_webhooks
      else
        yield cassette.vcr_cassette
      end
    end

    # Create and delete dummy test clock to wait for the rest webhooks to be received.
    # Stripe doesn’t guarantee delivery of events in the order in which they’re generated.
    # But waiting dummy test clock event lower the probability of webhook ordering problem.
    def wait_for_rest_webhooks
      time = Time.now
      name = "vcr_sw_fence_#{time.to_i}_#{SecureRandom.alphanumeric}"
      test_clock = nil
      @fence_mutex.synchronize do
        raise "Fence already used!" if @fence_test_clock_id

        @fence_signaled = false
        test_clock = Stripe::TestHelpers::TestClock.create(frozen_time: time.to_i, name: name)
        @fence_test_clock_id = test_clock.id
      end
      test_clock.delete
      @fence_mutex.synchronize do
        loop do
          break if @fence_signaled

          @fence_cond_var.wait(@fence_mutex, VcrStripeWebhook.configuration.timeout)
        end
        @fence_test_clock_id = nil
      end
    end

    private

    def receive_webhook(payload)
      event_hash = JSON.parse(payload)
      if @last_fence_event_created && event_hash["created"] < @last_fence_event_created
        logger.info "Ignore old event: #{event_hash["type"]}"
        return
      end

      logger.info "Server received event: #{event_hash["type"]} (cassette=#{@cassette&.name})"
      @cassette&.receive_event_payload(Event.new(event_hash["type"], event_hash))

      @fence_mutex.synchronize do
        if @fence_test_clock_id && event_hash["type"] == "test_helpers.test_clock.deleted" && event_hash.dig(
          "data", "object", "id"
        ) == @fence_test_clock_id
          @last_fence_event_created = event_hash["created"]
          @fence_signaled = true
          @fence_cond_var.signal
        end
      end
    end

    def logger
      VcrStripeWebhook.logger
    end
  end
end
