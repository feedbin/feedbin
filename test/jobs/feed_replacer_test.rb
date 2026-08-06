require "test_helper"

class FeedReplacerTest < ActiveSupport::TestCase
  setup do
    @user = users(:ben)
    @subscription = @user.subscriptions.first
    @old_feed = @subscription.feed
    @new_feed = feeds(:kottke)
    @discovered_feed = DiscoveredFeed.create!(site_url: @old_feed.site_url, feed_url: @new_feed.feed_url)
  end

  test "should move taggings to the new feed" do
    tag(@old_feed, "News")

    replace

    assert_equal [@new_feed.id], @user.taggings.reload.pluck(:feed_id)
  end

  test "should move taggings when already subscribed to the new feed" do
    @user.subscriptions.create!(feed: @new_feed)
    tag(@old_feed, "News")

    replace

    assert_equal [@new_feed.id], @user.taggings.reload.pluck(:feed_id)
  end

  test "should not duplicate a tagging the new feed already has" do
    @user.subscriptions.create!(feed: @new_feed)
    tag(@old_feed, "News")
    tag(@new_feed, "News")

    replace

    taggings = @user.taggings.reload
    assert_equal 1, taggings.count
    assert_equal @new_feed.id, taggings.first.feed_id
  end

  private

  def replace
    FeedFinder.stub(:feeds, [@new_feed]) do
      FeedReplacer.new.perform(@user.id, @subscription.id, @discovered_feed.id)
    end
  end

  def tag(feed, name)
    @user.taggings.create!(tag: Tag.where(name: name).first_or_create!, feed: feed)
  end
end
