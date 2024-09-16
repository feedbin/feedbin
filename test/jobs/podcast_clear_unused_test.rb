require "test_helper"

class PodcastClearUnusedTest < ActiveSupport::TestCase
  def setup
    @user = users(:ben)
    @podcast_subscription = @user.podcast_subscriptions.first
    @entry = create_entry(@podcast_subscription.feed)
  end

  test "destroys old hidden subscriptions without queued entries" do
    @podcast_subscription.hidden!
    @podcast_subscription.update(created_at: 2.months.ago)
    @podcast_subscription.queued_entries.destroy_all

    assert_difference "PodcastSubscription.count", -1 do
      PodcastClearUnused.new.perform
    end

    assert_not PodcastSubscription.exists?(@podcast_subscription.id)
  end

  test "does not destroy recent hidden subscriptions" do
    @podcast_subscription.hidden!
    @podcast_subscription.update(created_at: 2.weeks.ago)

    assert_no_difference "PodcastSubscription.count" do
      PodcastClearUnused.new.perform
    end

    assert PodcastSubscription.exists?(@podcast_subscription.id)
  end

  test "does not destroy old hidden subscriptions with queued entries" do
    @podcast_subscription.hidden!
    @podcast_subscription.update(created_at: 2.months.ago)

    assert_no_difference "PodcastSubscription.count" do
      PodcastClearUnused.new.perform
    end

    assert PodcastSubscription.exists?(@podcast_subscription.id)
  end

  test "does not destroy subscribed subscriptions" do
    @podcast_subscription.subscribed!

    assert_no_difference "PodcastSubscription.count" do
      PodcastClearUnused.new.perform
    end

    assert PodcastSubscription.exists?(@podcast_subscription.id)
  end
end