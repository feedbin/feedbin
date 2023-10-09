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

  test "should not change status of ignored subscription" do
    @subscription.fix_suggestion_ignored!
    FeedFixer.new.perform(@subscription.feed.id)
    FeedFixer.new.perform(@subscription.feed.id)
    assert(@subscription.reload.fix_suggestion_ignored?, "Subscription should not have a fix suggestion")
    refute(@user.reload.setting_on?(:fix_feeds_available))
  end
end
