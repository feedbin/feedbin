json.array!(@subscriptions) do |subscription|
  json.partial! "api/v2/subscriptions/subscription", subscription: subscription
end
