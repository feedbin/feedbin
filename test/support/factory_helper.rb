module FactoryHelper

  def create_feeds(user)
    flush_redis
    feeds = 3.times.map do
      url = Faker::Internet.url
      host = URI(url).host
      Feed.create(feed_url: url, host: host).tap do |feed|
        user.subscriptions.where(feed: feed).first_or_create
        entry = create_entry(feed)
        SearchIndexStore.new().perform("Entry", entry.id)
      end
    end
    Entry.__elasticsearch__.refresh_index!
    feeds
  end

  def create_entry(feed)
    feed.entries.create(
      title: Faker::Lorem.sentence,
      url: Faker::Internet.url,
      content: Faker::Lorem.paragraph,
      public_id: SecureRandom.hex,
    )
  end

  def mark_unread(user)
    user.entries.each do |entry|
      UnreadEntry.create_from_owners(user, entry)
    end
  end
end
