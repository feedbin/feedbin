class FeedImportFixer
  include Sidekiq::Worker
  include SidekiqHelper
  sidekiq_options queue: :default_critical

  def perform(user_id, import_item_id, discovered_feed_id = nil)
    user = User.find(user_id)
    import_item = user.import_items.find(import_item_id)

    discovered_feed = if discovered_feed_id
      DiscoveredFeed.find(discovered_feed_id)
    else
      import_item.discovered_feeds.order(created_at: :asc).take
    end

    return if discovered_feed.nil?

    feeds = begin
      FeedFinder.feeds(discovered_feed.feed_url, import_mode: true)
    rescue => exception
      []
    end

    return unless feeds.present?

    feed = feeds.first

    user.subscriptions.create_with(title: import_item.details[:title]).find_or_create_by(feed: feed)
    feed.tag(import_item.details[:tag], user, false) if import_item.details[:tag]
  end
end
