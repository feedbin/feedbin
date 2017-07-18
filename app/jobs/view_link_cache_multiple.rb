class ViewLinkCacheMultiple
  include Sidekiq::Worker
  sidekiq_options queue: :critical, retry: false

  def perform(user_id, entry_ids)
    user = User.find(user_id)
    unread_ids = user.unread_entries.where(entry_id: entry_ids).pluck(:entry_id)
    entries = Entry.select(:id, :feed_id, :url).where(id: unread_ids).includes(:feed)
    feed_ids = entries.map(&:feed_id)
    inline_on = user.subscriptions.where(feed_id: feed_ids, view_inline: true).pluck(:feed_id)

    entries.each do |entry|
      if inline_on.include?(entry.feed_id)
        key = "view_link_cache_multiple:%s" % Digest::SHA1.hexdigest(entry.fully_qualified_url)
        if Rails.cache.exist?(key)
          Librato.increment 'view_link_cache_multiple.cache_hit'
        else
          Rails.cache.write(key, key)
          Librato.increment 'view_link_cache_multiple.cache_miss'
        end
      end
    end

  end

end
