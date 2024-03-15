require "test_helper"

class PodcastSubscriptionTest < ActiveSupport::TestCase

  test "should not filter if empty" do
    podcast_subscription = podcast_subscriptions(:ben_daring_fireball)
    refute podcast_subscription.filtered?("subject")
  end

  test "should filter excluded term" do
    podcast_subscription = podcast_subscriptions(:ben_daring_fireball)
    podcast_subscription.download_filter_exclude!
    podcast_subscription.update(download_filter: "filter me, other")
    assert podcast_subscription.filtered?("filter me")
    refute podcast_subscription.filtered?("not me")
  end

  test "should not filter included term" do
    podcast_subscription = podcast_subscriptions(:ben_daring_fireball)
    podcast_subscription.download_filter_include!
    podcast_subscription.update(download_filter: "filter me, other")
    refute podcast_subscription.filtered?("filter me")
    assert podcast_subscription.filtered?("not a match")
  end
end
