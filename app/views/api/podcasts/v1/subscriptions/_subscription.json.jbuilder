json.id subscription.id
json.playlist_id subscription.playlist_id
json.partial! "api/v2/subscriptions/feed", subscription: subscription
json.status subscription.status
json.updated_at subscription.updated_at.iso8601(6)
json.created_at subscription.created_at.iso8601(6)