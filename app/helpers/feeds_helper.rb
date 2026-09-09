module FeedsHelper
  # A favicon is its own row with its own timestamp -- nothing writes to
  # the feed when one changes, so the key digests the favicon records. Both
  # collections arrive includes(:favicon), so this costs no query.
  def sidebar_feeds_cache_key(feeds)
    [feeds, feeds.map(&:title), feeds.map(&:favicon), "v4"]
  end

  # titles come from subscriptions, so a rename does not touch the feed's key
  def sidebar_tags_cache_key(tags)
    feeds = tags.flat_map(&:user_feeds)
    [tags, tags.map(&:user_feeds), feeds.map(&:title), feeds.map(&:favicon), "v10"]
  end
end
