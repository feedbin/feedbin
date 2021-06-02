module FactoryHelper
  def create_feeds(users, count = 3)
    flush_redis
    users = [*users]
    feeds = count.times.map {
      url = Faker::Internet.url
      host = URI(url).host
      Feed.create(feed_url: url, host: host, title: Faker::Lorem.sentence).tap do |feed|
        users.map do |user|
          user.subscriptions.where(feed: feed).first_or_create
        end
        entry = create_entry(feed)
        SearchIndexStore.new.perform("Entry", entry.id)
      end
    }
    Entry.__elasticsearch__.refresh_index!
    feeds
  end

  def create_entry(feed)
    feed.entries.create!(
      title: Faker::Lorem.sentence,
      url: Faker::Internet.url,
      content: Faker::Lorem.paragraph,
      public_id: SecureRandom.hex,
      entry_id: SecureRandom.hex,
      data: {
        enclosure_url: Faker::Internet.url
      }
    )
  end

  def mark_unread(user)
    user.entries.each do |entry|
      UnreadEntry.create_from_owners(user, entry)
    end
  end

  def create_tweet_entry(feed, option = "one")
    tweet = load_tweet(option)
    entry = create_entry(feed)
    entry.data["tweet"] = tweet
    entry.main_tweet_id = tweet["id"]
    entry.save!
    entry
  end

  def stripe_user
    plan = plans(:trial)
    card = StripeMock.generate_card_token(last4: "4242", exp_month: 99, exp_year: 3005)
    create_stripe_plan(plan)
    user = User.create(
      email: "cc@example.com",
      password: default_password,
      plan: plan
    )
    user.stripe_token = card
    user.save
    user
  end
end
