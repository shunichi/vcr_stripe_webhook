# frozen_string_literal: true

require "json"

RSpec.describe VcrStripeWebhook do
  it "has a version number" do
    expect(VcrStripeWebhook::VERSION).not_to be nil
  end

  it "gets webhook payload" do
    VcrStripeWebhook.use_cassette("create_customer") do |_vcr_cassette|
      stripe_customer = nil

      # Get webhook payload from Stripe server or current cassette
      webhook_payload_json = VcrStripeWebhook.receive_webhook("customer.created") do
        customer_params = {
          email: "test-user@example.com",
          name: "test-user"
        }
        stripe_customer = Stripe::Customer.create(customer_params)
      end

      payload_hash = JSON.parse(webhook_payload_json)
      expect(payload_hash["type"] == "customer.created")
      expect(payload_hash["object"] == "event")
      expect(payload_hash.dig("data", "object", "object") == "customer")
    ensure
      stripe_customer&.delete
    end
  end
end
