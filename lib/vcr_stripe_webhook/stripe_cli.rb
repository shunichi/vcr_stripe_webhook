# frozen_string_literal: true

module VcrStripeWebhook
  class StripeCLI
    def initialize(server_port, api_key)
      @server_port = server_port
      @api_key = api_key
      run
    end

    def terminate
      @stdout.close
      @read_out_thread.join
      @stderr.close
      @read_err_thread.join
      Process.kill(:TERM, @pid)
      Process.waitpid(@pid)
    end

    private

    def run
      spawn_process

      @ready_waiter = ReadyWaiter.new

      @read_out_thread = Thread.new do
        read_thread("OUT", @stdout)
      end
      @read_err_thread = Thread.new do
        read_thread("ERR", @stderr, ready_check: true)
      end

      logger.info "Waiting for Stripe CLI to be ready..."
      @ready_waiter.wait_ready
      self
    end

    def spawn_process
      env = { "STRIPE_API_KEY" => @api_key }
      r_out, w_out = IO.pipe
      r_err, w_err = IO.pipe
      command_and_args = ["stripe", "listen", "--forward-to", "localhost:#{@server_port}/"]
      logger.info "Spawning Stripe CLI: #{command_and_args.join(" ")}"
      @pid = spawn(env, *command_and_args, { out: w_out, err: w_err })
      w_out.close
      w_err.close
      @stdout = r_out
      @stderr = r_err
      logger.info "Stripe CLI PID=#{@pid}"
    rescue Errno::ENOENT
      raise "Could not spawn Stripe CLI"
    end

    def read_thread(prefix, io, ready_check: false)
      loop do
        line = io.gets(chomp: true)
        return if line.nil?

        @ready_waiter.signal_ready if ready_check && line.start_with?("Ready!")
        logger.info "Stripe CLI: #{prefix}: #{line}"
      rescue IOError
        # Closed in another thread
        break
      end
    end

    def logger
      VcrStripeWebhook.logger
    end

    class ReadyWaiter
      def initialize
        @ready = false
        @ready_mutex = Mutex.new
        @ready_cond_var = ConditionVariable.new
      end

      def wait_ready
        @ready_mutex.synchronize do
          loop do
            break if @ready

            @ready_cond_var.wait(@ready_mutex)
          end
        end
      end

      def signal_ready
        @ready_mutex.synchronize do
          @ready = true
          @ready_cond_var.signal
        end
      end
    end
  end
end
