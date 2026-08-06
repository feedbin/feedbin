require "test_helper"

module Search
  class TouchActionsTest < ActiveSupport::TestCase
    setup do
      @user = users(:new)
      @feed = create_feeds(@user, 1).first
      @tag = Tag.where(name: "Slice10").first_or_create!
      @tagging = Tagging.create!(user: @user, feed: @feed, tag: @tag)
      @action = @user.actions.create!(
        title: "test",
        query: "lorem",
        tag_ids: [@tag.id],
        actions: ["mark_read"]
      )
    end

    test "should touch action" do
      action = actions(:ben_one)
      TouchActions.new.perform([action.id])
      assert_not_equal action.updated_at, action.reload.updated_at
    end

    test "should recompute the feed set when the last tagging is removed" do
      assert_equal [@feed.id], @action.reload.computed_feed_ids

      @tagging.destroy
      TouchActions.new.perform([@action.id])

      assert_empty @action.reload.computed_feed_ids,
        "the action no longer covers any feed and its percolator has to follow"
    end

    test "should mark the action broken when no feeds remain" do
      @tagging.destroy
      TouchActions.new.perform([@action.id])

      assert @action.reload.broken?
  end

    test "should touch the actions that survive when one in the batch was destroyed" do
      action = actions(:ben_one)
      destroyed = Action.maximum(:id).to_i + 10_000

      assert_nothing_raised do
        TouchActions.new.perform([action.id, destroyed])
      end

      assert_not_equal action.updated_at, action.reload.updated_at
    end
  end
end
