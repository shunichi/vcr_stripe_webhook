# frozen_string_literal: true

require "logger"
require_relative "vcr_stripe_webhook/version"
require_relative "vcr_stripe_webhook/configuration"
require_relative "vcr_stripe_webhook/event_receiver"
require_relative "vcr_stripe_webhook/event_cassette"

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
        EventReceiver.instance.use_cassete(@current_event_cassette, &block)
        @current_event_cassette.serialize if @current_event_cassette.recording?
      ensure
        @current_event_cassette = nil
      end
    end

    def receive_webhook(event_type, timeout: configuration.timeout, &block)
      raise "No event cassete inserted." if current_event_cassette.nil?

      event = current_event_cassette.wait_for_event(event_type, timeout: timeout, &block)
      JSON.generate(event.value)
    end
  end
end
