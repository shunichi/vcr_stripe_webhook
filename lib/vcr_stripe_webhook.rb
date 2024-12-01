# frozen_string_literal: true

require "logger"
require "set"
require_relative "vcr_stripe_webhook/version"
require_relative "vcr_stripe_webhook/configuration"
require_relative "vcr_stripe_webhook/event_receiver"
require_relative "vcr_stripe_webhook/event_cassette"
require_relative "vcr_stripe_webhook/waiter"

module VcrStripeWebhook
  class << self
    attr_reader :server, :current_event_cassette
    attr_writer :logger

    def stop
      EventReceiver.terminate
    end

    def configuration
      @configuration ||= VcrStripeWebhook::Configuration.new
    end

    def logger
      @logger ||= Logger.new("log/vcr_stripe_webhook.log")
    end

    def use_cassette(name, options = {}, &block)
      VCR.use_cassette(name, options) do |vcr_cassette|
        @current_event_cassette = EventCassette.new(name, vcr_cassette, vcr_cassette.recording?)
        EventReceiver.instance.use_cassette(@current_event_cassette, &block)
        @current_event_cassette.serialize if @current_event_cassette.recording?
      ensure
        @current_event_cassette = nil
      end
    end

    def receive_webhook_events(event_types: nil, wait_until: nil, timeout: configuration.timeout, &block)
      raise "No event cassette inserted." if current_event_cassette.nil?
      raise "event_types or wait_until must be passed as an argument." if event_types.nil? && wait_until.nil?

      waiter =
        if event_types
          EventTypeWaiter.new(event_types)
        else
          ProcWaiter.new(wait_until)
        end
      current_event_cassette.wait_for_events(waiter, timeout: timeout, &block)
    end

    def receive_webhook_event(event_type, timeout: configuration.timeout, &block)
      events = receive_webhook_events(event_types: [event_type], timeout: timeout, &block)
      events.find { |event| event.type == event_type }
    end
  end
end
