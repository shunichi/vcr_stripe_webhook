# VcrStripeWebhook

Record and replay Stripe webhooks during integration test.

## Requirements

- [vcr gem](https://github.com/vcr/vcr)
- [Stripe CLI](https://stripe.com/docs/stripe-cli)

## Installation

Add this gem to Gemfile.

```
gem 'vcr_stripe_webhook', github: 'shunichi/vcr_stripe_webhook'
```

## Usage

```ruby
# Set Stripe API key for test mode
Stripe.api_key = 'sk_test_...'
```

Use `VcrStripeWebhook.use_cassette` instead of `VCR.use_cassette`.

```ruby
# This method wraps VCR.use_cassette
VcrStripeWebhook.use_cassette('create_customer') do |vcr_cassette|
  stripe_customer = nil

  # Get webhook payload from Stripe server or current cassette
  webhook_event = VcrStripeWebhook.receive_webhook_event('customer.created') do
    customer_params = {
      email: 'test-user@example.com',
      name: 'test-user',
    }
    stripe_customer = Stripe::Customer.create(customer_params)
  end

  # Call your webhook manually
  post your_stripe_webhook_path, params: webhook_event.as_json,
    headers: { 'Content-Type: application/json' }

  # Insert assertion here
ensure
  stripe_customer&.delete
end
```

On the first run, this code records HTTP requests/responses with VCR gem and additionally records received webhooks with vcr_stripe_webhook gem.
On the second run or later, it replays the recorded requests, responses and webhooks.

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake spec` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and the created tag, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/shunichi/vcr_stripe_webhook.

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).
