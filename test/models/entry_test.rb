require "test_helper"

class EntryTest < ActiveSupport::TestCase
  setup do
    user = users(:ben)
    feed = user.feeds.first
    @entry = feed.entries.build(
      public_id: SecureRandom.hex,
      content: "<p>#{Faker::Lorem.paragraph}</p>"
    )
  end

  test "should add to created_at cache" do
    @entry.save
    key = FeedbinUtils.redis_created_at_key(@entry.feed_id)
    created_at = "%10.6f" % @entry.reload.created_at
    score = $redis[:entries].with { |redis| redis.zscore(key, @entry.reload.id) }
    assert_equal("%10.5f" % created_at.to_i, "%10.5f" % score.to_i)
  end

  test "should add to published cache" do
    @entry.save
    key = FeedbinUtils.redis_published_key(@entry.feed_id)
    published = "%10.6f" % @entry.reload.published
    score = $redis[:entries].with { |redis| redis.zscore(key, @entry.reload.id) }

    assert_equal(published.to_i, score.to_i)
  end

  test "should always have a published date" do
    assert_nil(@entry.published)
    @entry.save
    assert_not_nil(@entry.reload.published)
  end

  test "should cache id" do
    @entry.save
    assert_equal(@entry.content.length, $redis[:refresher].with { |redis| redis.get(@entry.public_id).to_i })
  end

  test "should create summary" do
    @entry.save
    assert_not_nil(@entry.reload.summary)
  end

  test "should update summary" do
    @entry.save
    summary = @entry.reload.summary
    @entry.update(content: "<p>#{Faker::Lorem.paragraph}</p>")
    assert_not_equal(summary, @entry.reload.summary)
  end

  test "should enqueue find_images" do
    flush_redis
    assert_difference "EntryImage.jobs.size", +1 do
      @entry.save
      job = EntryImage.jobs.last
      assert_equal([@entry.reload.public_id], job["args"])
    end
  end

  test "should mark unread" do
    assert_difference "UnreadEntry.count", +1 do
      @entry.save
    end
  end

  test "should increment feed_stat" do
    assert_difference "FeedStat.count", +1 do
      @entry.save
    end
  end

  test "should update last_published_entry" do
    last_published_entry = @entry.feed.last_published_entry
    @entry.save
    assert_not_equal(last_published_entry, @entry.reload.feed.last_published_entry)
  end

  test "should get fully qualifed url" do
    @entry.url = "/test"
    assert_equal("http://daringfireball.net/test", @entry.fully_qualified_url)
  end
end
