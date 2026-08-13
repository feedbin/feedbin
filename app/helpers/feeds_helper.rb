module FeedsHelper
  # The sidebar renders a FaviconComponent per feed, and a favicon is its own
  # row with its own timestamp -- nothing writes to the feed when one changes.
  # Digesting the records is what makes it safe to remove the TouchFeeds
  # fan-out: invalidation stops depending on writing to every feed on the
  # host. Both collections reach here already includes(:favicon), so it
  # costs no query.
  def self.sidebar_feeds_cache_key(feeds)
    [feeds, feeds.map(&:title), feeds.map(&:favicon), "v4"]
  end

  # titles come from subscriptions, so a rename does not touch the feed's key
  def self.sidebar_tags_cache_key(tags)
    feeds = tags.flat_map(&:user_feeds)
    [tags, tags.map(&:user_feeds), feeds.map(&:title), feeds.map(&:favicon), "v10"]
  end

  def sidebar_feeds_cache_key(feeds)
    FeedsHelper.sidebar_feeds_cache_key(feeds)
  end

  def sidebar_tags_cache_key(tags)
    FeedsHelper.sidebar_tags_cache_key(tags)
  end
end
