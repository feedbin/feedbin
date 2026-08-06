require "test_helper"

class FeedReplacerTest < ActiveSupport::TestCase
  setup do
    @user = users(:ben)
    create_feeds(@user)
    @subscription = @user.subscriptions.first
    @old_feed = @subscription.feed
    @new_feed = Feed.where.not(id: @old_feed.id).first
    @user.subscriptions.where(feed: @new_feed).destroy_all
    @discovered = DiscoveredFeed.create!(site_url: @old_feed.site_url, feed_url: @new_feed.feed_url)
    @subscription.fix_suggestion_present!
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

  test "moves the subscription to the discovered feed" do
    replace

    assert_equal @new_feed, @subscription.reload.feed
    assert @subscription.fix_suggestion_none?
  end

  test "a second delivery of the same job is a no-op" do
    FeedFinder.stub(:feeds, [@new_feed]) do
      FeedReplacer.new.perform(@user.id, @subscription.id, @discovered.id)

      assert_nothing_raised do
        FeedReplacer.new.perform(@user.id, @subscription.id, @discovered.id)
      end
    end

    assert_equal @new_feed, @subscription.reload.feed
    assert @subscription.fix_suggestion_none?, "a retry must not undo a replacement that already succeeded"
  end

  test "a second delivery is a no-op when the subscription was replaced by an existing one" do
    existing = @user.subscriptions.create!(feed: @new_feed)

    FeedFinder.stub(:feeds, [@new_feed]) do
      FeedReplacer.new.perform(@user.id, @subscription.id, @discovered.id)

      assert_nothing_raised do
        FeedReplacer.new.perform(@user.id, @subscription.id, @discovered.id)
      end
    end

    assert_nil Subscription.find_by(id: @subscription.id)
    assert existing.reload.persisted?
  end

  test "still reports a discovered feed that resolves to the feed being fixed" do
    reported = []

    ErrorService.stub(:notify, ->(params) { reported << params }) do
      FeedFinder.stub(:feeds, [@old_feed]) do
        FeedReplacer.new.perform(@user.id, @subscription.id, @discovered.id)
      end
    end

    assert reported.any? { |params| params[:error_message] == "same feed" }
    assert @subscription.reload.fix_suggestion_ignored?
  end

  test "leaves the subscription alone when the rewrite that follows it fails" do
    @user.actions.first.update_column(:feed_ids, [@old_feed.id.to_s])

    FeedFinder.stub(:feeds, [@new_feed]) do
      Action.stub_any_instance(:update, ->(*) { raise "boom" }) do
        assert_raises(RuntimeError) do
          FeedReplacer.new.perform(@user.id, @subscription.id, @discovered.id)
        end
      end
    end

    assert_equal @old_feed, @subscription.reload.feed,
      "a half-applied replacement leaves actions pointing at a feed the user is no longer subscribed to"
  end

  private

  def replace
    FeedFinder.stub(:feeds, [@new_feed]) do
      FeedReplacer.new.perform(@user.id, @subscription.id, @discovered.id)
    end
  end

  def tag(feed, name)
    @user.taggings.create!(tag: Tag.where(name: name).first_or_create!, feed: feed)
  end
end
