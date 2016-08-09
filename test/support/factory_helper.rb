module FactoryHelper

  def create_feeds(user)
    feeds = 3.times.map do
      Feed.create(feed_url: Faker::Internet.url).tap do |feed|
        user.subscriptions.where(feed: feed).first_or_create
        create_entry(feed)
      end
    end
    Entry.__elasticsearch__.refresh_index!
    feeds
  end

  def create_entry(feed)
    entry = feed.entries.create(
      title: Faker::Lorem.sentence,
      url: Faker::Internet.url,
      content: Faker::Lorem.paragraph,
      public_id: Faker::Internet.slug,
    )
    SearchIndexStore.new().perform("Entry", entry.id)
  end
end
