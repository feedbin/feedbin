if defined?(@subscription)
  json.partial! "api/v2/subscriptions/subscription", subscription: @subscription
elsif defined?(@options)
  json.partial! "api/v2/subscriptions/options", options: @options
end
