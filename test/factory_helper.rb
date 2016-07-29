module FactoryHelper

  def create_feeds(user)
    3.times.map do
      Feed.create(feed_url: Faker::Internet.url).tap do |feed|
        user.subscriptions.where(feed: feed).first_or_create
        create_entry(feed)
      end
    end
  end

  def create_entry(feed)
    feed.entries.create(
      title: Faker::Lorem.sentence,
      url: Faker::Internet.url,
      content: Faker::Lorem.paragraph,
      public_id: Faker::Internet.slug,
    )
  end
end
