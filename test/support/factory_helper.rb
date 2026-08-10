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
      end
    }
    entries = feeds.flat_map { bulk_create_entries(_1, 1, users: users) }
    index_entries(entries)
    feeds
  end

  # One bulk request rather than Search::SearchIndexStore per entry — the
  # store job also percolates each document against the actions index (three
  # extra requests per entry), which no create_feeds caller depends on. Tests
  # that assert percolation invoke SearchIndexStore themselves.
  def index_entries(entries)
    records = entries.map do |entry|
      Search::BulkRecord.new(
        action: "index",
        index: Search.index_name(Entry.table_name),
        id: entry.id,
        document: entry.search_data
      )
    end
    Search.client do |client|
      client.bulk(records)
      client.refresh
    end
  end

  # Bulk-inserts bare entries in one statement, skipping Entry's per-create
  # callbacks — an order of magnitude cheaper than create! for tests that
  # only need rows to exist. Pass users: to also mark the entries unread for
  # them, the way the mark_as_unread callback would have. Tests that depend
  # on other callback side effects should use create_entry.
  def bulk_create_entries(feed, count, users: [], attributes: {})
    now = Time.now
    rows = count.times.map do |index|
      {
        feed_id: feed.id,
        title: Faker::Lorem.sentence,
        url: Faker::Internet.url,
        author: SecureRandom.hex,
        content: Faker::Lorem.paragraph,
        public_id: SecureRandom.hex,
        entry_id: SecureRandom.hex,
        data: {enclosure_url: Faker::Internet.url},
        published: now + index,
        created_at: now,
        updated_at: now
      }.merge(attributes)
    end
    ids = Entry.insert_all(rows, returning: [:id]).rows.flatten
    entries = Entry.where(id: ids).order(:id).to_a

    unreads = [*users].flat_map { |user|
      entries.map {
        UnreadEntry.new(user_id: user.id, feed_id: feed.id, entry_id: _1.id, published: _1.published, entry_created_at: _1.created_at)
      }
    }
    UnreadEntry.import(unreads, validate: false, on_duplicate_key_ignore: true) if unreads.present?

    entries
  end

  def create_entry(feed)
    feed.entries.create!(
      title: Faker::Lorem.sentence,
      url: Faker::Internet.url,
      content: Faker::Lorem.paragraph,
      public_id: SecureRandom.hex,
      entry_id: SecureRandom.hex,
      author: SecureRandom.hex,
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
    create_stripe_plan(plan)
    user = User.create(
      email: "cc@example.com",
      password: default_password,
      plan: plan
    )
    stub_payment_methods do
      user.stripe_token = "pm_test_card"
      user.save
    end
    user
  end
end
