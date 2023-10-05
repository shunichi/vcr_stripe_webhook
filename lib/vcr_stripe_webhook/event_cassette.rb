# frozen_string_literal: true

require "yaml"
require "fileutils"
require_relative "event"

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

    def wait_for_event(event_type, timeout:, &block)
      if recording?
        record_and_wait_for_event(event_type, timeout: timeout, &block)
      else
        replay_and_wait_for_event(event_type, &block)
      end
    end

    def receive_event_payload(event_payload)
      @mutex.synchronize do
        @data.events.push(Event.new(event_payload["type"], event_payload))
      end
    end

    def serialize
      @data.serialize(path)
    end

    private

    def record_and_wait_for_event(event_type, timeout:)
      logger.info "Record and wait for: #{event_type}"
      wait_start = @data.events.size

      yield

      start_time = Time.now
      loop do
        result_event = nil
        @mutex.synchronize do
          wait_end = @data.events.size
          result_event = @data.events[wait_start...wait_end].find do |event|
            event.type == event_type
          end
          @data.waits.push(Wait.new(wait_start, wait_end)) if result_event
        end

        return result_event if result_event
        raise "No '#{event_type}' event received." if Time.now - start_time > timeout

        sleep 0.5
      end
    end

    def replay_and_wait_for_event(event_type)
      logger.info "Replay and wait for: #{event_type}"
      wait = @data.waits[@wait_counter]
      if wait.nil?
        # TODO: 適切なメッセージ
        raise "No wait data."
      end

      yield

      result_event = @data.events[wait.start...wait.end].find do |event|
        event.type == event_type
      end
      if result_event.nil?
        # TODO: 適切なメッセージ
        raise "No event."
      end

      @wait_counter += 1
      result_event
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
