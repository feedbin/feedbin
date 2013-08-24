json.id subscription.id
json.created_at subscription.created_at.iso8601(6)
json.partial! "api/v2/subscriptions/feed", subscription: subscription
