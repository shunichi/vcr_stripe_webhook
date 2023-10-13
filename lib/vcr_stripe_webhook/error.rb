module VcrStripeWebhook
  class Error < StandardError
  end

  class EventWaitTimeout < Error
  end

  class CassetteDataError < Error
  end
end
