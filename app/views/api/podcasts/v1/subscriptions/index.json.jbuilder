json.array!(@subscriptions) do |subscription|
  json.partial! "subscription", subscription: subscription
end
