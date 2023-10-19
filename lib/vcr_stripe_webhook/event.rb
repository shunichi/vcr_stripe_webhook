# frozen_string_literal: true

module VcrStripeWebhook
  class Event
    attr_reader :type

    def initialize(type, event_hash)
      @type = type
      @event_hash = event_hash
    end

    def to_h
      {
        "type" => type,
        "value" => as_hash
      }
    end

    def as_hash
      @event_hash
    end

    def as_json
      @json = JSON.generate(@event_hash)
    end

    class << self
      def from_hash(hash)
        Event.new(hash["type"], hash["value"])
      end
    end
  end
end
