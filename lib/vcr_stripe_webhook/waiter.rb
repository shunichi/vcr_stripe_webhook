module VcrStripeWebhook
  class ProcWaiter
    def initialize(proc)
      @proc
    end

    def call(events)
      @proc.call(events)
    end

    def timeout_message(events, recording:)
      events_words = recording ? "received events" : "the recorded events"
      "wait_until proc does not return true with #{events_words}."
    end
  end

  class EventTypeWaiter
    attr_reader :event_types

    def initialize(event_types)
      @event_types = event_types
    end

    def call(events)
      type_set = events.map(&:type).to_set
      event_types.all? { |type| type_set.member?(type) }
    end

    def timeout_message(events, recording:)
      type_set = events.map(&:type).to_set
      missing_event_types = event_types.select { |type| !type_set.member?(type) }
      events_words = recording ? "Received events" : "The recorded events"
      types_words = missing_event_types.map { |type| "'#{type}'" }.join(', ')
      "#{events_words} don't contain #{types_words}."
    end
  end
end
