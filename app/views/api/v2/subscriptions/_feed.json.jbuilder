json.feed_id subscription.feed.id
json.title subscription.title || subscription.feed.title
json.extract! subscription.feed, :feed_url, :site_url
