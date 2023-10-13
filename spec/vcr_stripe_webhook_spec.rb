# frozen_string_literal: true

require "json"

RSpec.describe VcrStripeWebhook do
  describe ".receive_webhook_event" do
    it "returns a webhook event" do
      VcrStripeWebhook.use_cassette("create_customer") do |_vcr_cassette|
        stripe_customer = nil

        # Get webhook payload from Stripe server or current cassette
        webhook_event = VcrStripeWebhook.receive_webhook_event("customer.created") do
          customer_params = {
            email: "test-user@example.com",
            name: "test-user"
          }
          stripe_customer = Stripe::Customer.create(customer_params)
        end

        event_hash = webhook_event.as_hash
        expect(event_hash["type"] == "customer.created")
        expect(event_hash["object"] == "event")
        expect(event_hash.dig("data", "object", "object") == "customer")
      ensure
        stripe_customer&.delete
      end
    end
  end

  describe ".receive_webhook_events" do
    it "returns multiple webhook events" do
      VcrStripeWebhook.use_cassette("create_customer_and_attach_payment_method") do |_vcr_cassette|
        stripe_customer = nil

        webhook_events = VcrStripeWebhook.receive_webhook_events(event_types: %w[customer.created payment_method.attached]) do
          customer_params = {
            email: "test-user@example.com",
            name: "test-user"
          }
          stripe_customer = Stripe::Customer.create(customer_params)

          stripe_payment_method = Stripe::PaymentMethod.retrieve('pm_card_visa')
          stripe_payment_method.attach(customer: stripe_customer.id)
        end

        recevied_event_types = webhook_events.map(&:type)
        expect(recevied_event_types).to include "customer.created"
        expect(recevied_event_types).to include "payment_method.attached"
      ensure
        stripe_customer&.delete
      end
    end
  end
end
