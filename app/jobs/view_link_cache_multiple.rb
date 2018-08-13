class ViewLinkCacheMultiple
  include Sidekiq::Worker
  sidekiq_options queue: :low, retry: false

  def perform(user_id, entry_ids)
    user = User.find(user_id)
    unread_ids = user.unread_entries.where(entry_id: entry_ids).pluck(:entry_id)
    entries = Entry.select(:id, :feed_id, :url).where(id: unread_ids).includes(:feed)
    feed_ids = entries.map(&:feed_id)
    inline_on = user.subscriptions.where(feed_id: feed_ids, view_inline: true).pluck(:feed_id)

    entries.each do |entry|
      if inline_on.include?(entry.feed_id)
        url = entry.fully_qualified_url
        key = FeedbinUtils.page_cache_key(url)
        Rails.cache.fetch(key) do
          Librato.increment "view_link_cache_multiple.cache_miss"
          MercuryParser.parse(url)
        end
      end
    end
  end
end
