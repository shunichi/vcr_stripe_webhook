# frozen_string_literal: true

require "yaml"
require "fileutils"
require_relative "event"
require_relative "error"

module VcrStripeWebhook
  class EventCassette
    attr_reader :name, :vcr_cassette

    def initialize(name, vcr_cassette, recording)
      @mutex = Mutex.new
      @name = name
      @vcr_cassette = vcr_cassette
      @recording = recording
      if recording
        @data = Data.new
      else
        @data = Data.deserialze(path)
        @wait_counter = 0
      end
    end

    def path
      dir = VcrStripeWebhook.configuration.cassette_library_dir
      File.join(dir, "#{name}.stripe_webhooks.yml")
    end

    def recording?
      @recording
    end

    def wait_for_events(waiter, timeout:, &block)
      if recording?
        record_and_wait_for_events(waiter, timeout: timeout, &block)
      else
        replay_and_wait_for_events(waiter, &block)
      end
    end

    def receive_event_payload(event)
      @mutex.synchronize do
        @data.events.push(event)
      end
    end

    def serialize
      @data.serialize(path)
    end

    private

    def record_and_wait_for_events(waiter, timeout:)
      wait_start = @data.events.size

      yield

      start_time = Time.now
      loop do
        finished = false
        target_events = nil
        @mutex.synchronize do
          wait_end = @data.events.size
          target_events = @data.events[wait_start...wait_end]
          finished = waiter.call(target_events)
          @data.waits.push(Wait.new(wait_start, wait_end)) if finished
        end

        return target_events if finished

        if Time.now - start_time > timeout
          message = waiter.timeout_message(target_events, recording: true)
          raise EventWaitTimeout, message
        end

        sleep 0.5
      end
    end

    def replay_and_wait_for_events(waiter)
      wait = @data.waits[@wait_counter]
      if wait.nil?
        raise CassetteDataError, <<~ERROR_MESSAGE
          receive_webhook_event(s) calls is more than the calls in the recorded data.
          If you modify test code after recording, record real webhooks again.
        ERROR_MESSAGE
      end

      yield

      target_events = @data.events[wait.start...wait.end]
      finished = waiter.call(target_events)
      unless finished
        message = waiter.timeout_message(target_events, recording: false)
        raise raise CassetteDataError, message
      end

      @wait_counter += 1
      target_events
    end

    def logger
      VcrStripeWebhook.logger
    end

    class Wait
      attr_reader :start, :end

      def initialize(wait_start, wait_end)
        @start = wait_start
        @end = wait_end
      end

      def to_h
        {
          "start" => start,
          "end" => self.end
        }
      end

      class << self
        def from_hash(hash)
          Wait.new(hash["start"], hash["end"])
        end
      end
    end

    class Data
      attr_reader :events, :waits

      def initialize(events: [], waits: [])
        @events = events
        @waits = waits
      end

      def serialize(path)
        yaml = YAML.dump({
                           "events" => @events.map(&:to_h),
                           "waits" => @waits.map(&:to_h)
                         })
        FileUtils.mkdir_p File.dirname(path)
        File.write(path, yaml)
      end

      class << self
        def deserialze(path)
          yaml = YAML.safe_load_file(path, permitted_classes: [])
          events = yaml["events"].map { |event_hash| Event.from_hash(event_hash) }
          waits = yaml["waits"].map { |hash| Wait.from_hash(hash) }
          Data.new(events: events, waits: waits)
        end
      end
    end
  end
end
