# frozen_string_literal: true

module VcrStripeWebhook
  class Configuration
    DEFAULT_TIMEOUT_SEC = 5

    attr_writer :timeout, :cassette_library_dir, :stripe_api_key

    def timeout
      @timeout ||= DEFAULT_TIMEOUT_SEC
    end

    def cassette_library_dir
      @cassette_library_dir ||=
        File.join(VCR.configuration.cassette_library_dir, "stripe_webhooks")
    end

    def stripe_api_key
      @stripe_api_key ||= Stripe.api_key
    end
  end
end
