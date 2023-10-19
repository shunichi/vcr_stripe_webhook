# frozen_string_literal: true

require "dotenv/load"
require "stripe"
require "webmock/rspec"
require "vcr"
require "vcr_stripe_webhook"
require "fileutils"

RSpec.configure do |config|
  # Enable flags like --only-failures and --next-failure
  config.example_status_persistence_file_path = ".rspec_status"

  # Disable RSpec exposing methods globally on `Module` and `main`
  config.disable_monkey_patching!

  config.expect_with :rspec do |c|
    c.syntax = :expect
  end

  FileUtils.mkdir_p "log"

  Stripe.api_key = ENV.fetch("VCR_STRIPE_WEBHOOK_API_KEY")

  VCR.configure do |c|
    c.cassette_library_dir = "spec/vcr"
    c.hook_into :webmock
    c.allow_http_connections_when_no_cassette = true
    c.ignore_localhost = true
    c.filter_sensitive_data("<STRIPE_API_KEY>") { ENV.fetch("VCR_STRIPE_WEBHOOK_API_KEY") }

    c.default_cassette_options[:record] = ENV.fetch("VCR_RECORD", "once").to_sym
    c.default_cassette_options[:drop_unused_requests] = true
  end
end
