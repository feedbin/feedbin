class FeedImporter
  include Sidekiq::Worker
  sidekiq_options queue: :critical, retry: false

  def perform(import_item_id)
    import_item = ImportItem.find(import_item_id)
    user = import_item.import.user

    finder = FeedFinder.new(import_item.details[:xml_url])
    feeds = finder.create_feeds!
    if feeds
      feed = feeds.first
      subscription = user.subscriptions.find_or_create_by(feed: feed)
      if import_item.details[:title] && subscription
        subscription.update(title: import_item.details[:title])
      end
      if import_item.details[:tag]
        feed.tag(import_item.details[:tag], user, false)
      end
    end
  rescue ActiveRecord::RecordNotFound
  end
end
