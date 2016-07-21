require 'test_helper'

class ActionTest < ActiveSupport::TestCase
  def setup
    @user = users(:ben)
    @action = actions(:ben_one)
  end

  test "should be valid" do
    assert @action.valid?
  end

  test "feeds should be present" do
    @action.feed_ids = []
    @action.tag_ids = []
    @action.all_feeds = false
    assert_not @action.valid?
  end

  test "must be subscribed to requested feeds" do
    feed = Feed.create
    action = @user.actions.build(action_params([feed.id]))
    assert_not action.computed_feed_ids.include?(feed.id)
  end

  test "saved to elasticsearch" do
    feed = feeds(:daring_fireball)
    action = @user.actions.create(action_params([feed.id]))
    assert action._percolator['found'] == true
  end

  private

  def action_params(feed_ids)
    {
      title: "Star",
      query: "john",
      all_feeds: false,
      feed_ids: feed_ids,
      actions: ["star"]
    }
  end
end
