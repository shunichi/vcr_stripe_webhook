# frozen_string_literal: true

require "socket"

module VcrStripeWebhook
  # Tiny web server for stripe webhook
  class Server
    attr_reader :tcp_server, :port

    def initialize(port = 0, &block)
      run(port, &block)
    end

    def close
      logger.info "Closing Server"
      tcp_server.close
    end

    def wait_event(event_type)
      @event_waiter.wait(event_type)
    end

    def join
      @accept_thread.join
    end

    private

    def run(port, &block)
      @tcp_server = TCPServer.open(port)
      _family, port, host, _ip = tcp_server.addr
      @port = port
      logger.info "Server is on #{[host, port].join(":")}"

      @block = block
      @accept_thread = Thread.start do
        run_thread
      end
    end

    def run_thread
      loop do
        socket = tcp_server.accept
        Thread.start(socket) do |s|
          request = RequestParser.new(s)

          if request.json_value.nil?
            s.write("HTTP/1.1 400\r\n\r\n")
          else
            @block&.call(request.json_value)
            s.write("HTTP/1.1 204\r\n\r\n")
          end
        ensure
          s.close
        end
      end
    rescue IOError
      # Closed in another thread
    end

    def logger
      VcrStripeWebhook.logger
    end

    class RequestParser
      MAX_HEADER_LENGTH = 16 * 1024

      attr_reader :method, :path, :headers

      def initialize(socket)
        @method, @path = read_start_line(socket)
        @headers = read_headers(socket)
        return unless content_length

        @body = socket.read(content_length)
      end

      def content_length
        @content_length ||= headers["content-length"]&.to_i
      end

      def content_type
        return @content_type if defined?(@content_type)

        if headers["content-type"]
          @content_type, _attributes = headers["content-type"].split(/;\s+/, 2)
        else
          @content_type = nil
        end
        @content_type
      end

      def json_value
        return @json_value if defined?(@json_value)

        @json_value =
          if content_type == "application/json"
            begin
              JSON.parse(@body)
            rescue StandardError
              nil
            end
          end
      end

      private

      def read_start_line(socket)
        line = socket.gets("\n")
        method, path, _http_version = line.split(" ", 3)
        [method, path]
      end

      def read_headers(socket)
        headers = {}
        loop do
          line = socket.gets("\n", MAX_HEADER_LENGTH, chomp: true)
          break if line.nil? || line.empty?

          key, value = line.split(/:\s+/, 2).map(&:strip)
          headers[key.downcase] = value
        end
        headers
      end

      def logger
        VcrStripeWebhook.logger
      end
    end
  end
end
