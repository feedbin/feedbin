json.subscriptions @subscriptions do |subscription|
  json.extract! subscription, :id, :feed_id, :created_at
end