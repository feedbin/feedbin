require "test_helper"

class FeedFixerTest < ActiveSupport::TestCase
  setup do
    @user = users(:ben)
    @subscription = @user.subscriptions.first

    feed_url = "https://example.com/feed/"

    stub_request(:get, @subscription.feed.site_url)
      .to_return(body: %(<link rel="alternate" type="application/atom+xml" href="#{feed_url}"/>))

    stub_request_file("atom.xml", feed_url)

    24.times do
      @subscription.feed.crawl_data.download_error(Exception.new)
    end
    @subscription.feed.save
  end

  test "should create options" do
    assert_difference -> { DiscoveredFeed.count }, +1 do
      assert_difference -> { FaviconCrawler::Finder.jobs.count }, +1 do
        FeedFixer.new.perform(@subscription.feed.id)
      end
    end

    discovered_feed = DiscoveredFeed.first
    assert_equal(@subscription.feed.site_url, discovered_feed.site_url)

    assert(@subscription.reload.fix_suggestion_present?, "Subscription should have a fix suggestion")
    assert(@user.reload.setting_on?(:fix_feeds_available))
  end

  test "should skip same feed url" do
    feed_url = @subscription.feed.feed_url

    stub_request(:get, @subscription.feed.site_url)
      .to_return(body: %(<link rel="alternate" type="application/atom+xml" href="#{feed_url}"/>))

    stub_request_file("atom.xml", feed_url)

    assert_no_difference -> { DiscoveredFeed.count } do
      FeedFixer.new.perform(@subscription.feed.id)
    end
  end

  test "should recover a discovered feed a concurrent job inserted first" do
    site_url = "https://race.example.com/"
    feed_url = "https://race.example.com/feed/"

    @subscription.feed.update!(site_url: site_url)
    stub_request(:get, site_url)
      .to_return(body: %(<link rel="alternate" type="application/atom+xml" href="#{feed_url}"/>))
    stub_request_file("atom.xml", feed_url)

    # Two feeds can share a site_url, so two FeedFixer jobs discover the same
    # (site_url, feed_url) pair concurrently. Commit the winner's row from
    # another connection between our lookup and our INSERT, so ours is the one
    # the unique index rejects. The committed row outlives this test's
    # transaction, so it is cleaned up in after_teardown.
    @committed_site_url = site_url

    outside_transaction do |other_job|
      raced = false
      race_winner = ->(_record) do
        next if raced
        raced = true
        other_job.execute(<<~SQL, site_url, feed_url)
          INSERT INTO discovered_feeds (site_url, feed_url, created_at, updated_at)
          VALUES (?, ?, now(), now())
        SQL
      end
      DiscoveredFeed.set_callback(:create, :before, race_winner)

      begin
        assert_difference -> { DiscoveredFeed.count }, +1 do
          FeedFixer.new.perform(@subscription.feed.id)
        end
        assert raced, "the race was never triggered"
        assert_equal 1, DiscoveredFeed.where(site_url: site_url, feed_url: feed_url).count
      ensure
        DiscoveredFeed.skip_callback(:create, :before, race_winner)
      end
    end
  end

  # Runs after the fixture transaction has rolled back, so the DELETE does not
  # wait on rows this test left uncommitted.
  def after_teardown
    super
    return unless @committed_site_url
    outside_transaction do |connection|
      connection.execute("DELETE FROM discovered_feeds WHERE site_url = ?", @committed_site_url)
    end
  end

  test "should not change status of ignored subscription" do
    @subscription.fix_suggestion_ignored!
    FeedFixer.new.perform(@subscription.feed.id)
    FeedFixer.new.perform(@subscription.feed.id)
    assert(@subscription.reload.fix_suggestion_ignored?, "Subscription should not have a fix suggestion")
    refute(@user.reload.setting_on?(:fix_feeds_available))
  end
end
