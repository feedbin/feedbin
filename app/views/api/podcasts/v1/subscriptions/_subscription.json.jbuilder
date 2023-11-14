json.extract! subscription, :id, :playlist_id, :status, :chapter_filter, :chapter_filter_type, :download_filter, :download_filter_type
json.partial! "api/v2/subscriptions/feed", subscription: subscription
json.updated_at subscription.updated_at.iso8601(6)
json.created_at subscription.created_at.iso8601(6)