# frozen_string_literal: true

module VcrStripeWebhook
  class Event
    attr_reader :type, :value

    def initialize(type, value)
      @type = type
      @value = value
    end

    def to_h
      {
        "type" => type,
        "value" => value
      }
    end

    class << self
      def from_hash(hash)
        Event.new(hash["type"], hash["value"])
      end
    end
  end
end
