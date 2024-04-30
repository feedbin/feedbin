json.extract! subscription, :id, :feed_id, :playlist_id, :status,
                            :chapter_filter, :chapter_filter_type,
                            :download_filter, :download_filter_type
json.title subscription.title
json.extract! subscription.feed, :feed_url, :site_url
json.updated_at subscription.updated_at.iso8601(6)
json.created_at subscription.created_at.iso8601(6)