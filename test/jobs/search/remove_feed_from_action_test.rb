require "test_helper"

module Search
  class RemoveFeedFromActionTest < ActiveSupport::TestCase
    setup do
      clear_search
      @user = users(:new)
      @feeds = create_feeds(@user, 2)
      @feed_to_remove = @feeds.first
      @other_feed = @feeds.last
    end

    test "removes the feed_id from each of the user's actions" do
      action = @user.actions.create!(
        title: "test",
        query: "lorem",
        feed_ids: [@feed_to_remove.id.to_s, @other_feed.id.to_s],
        actions: ["mark_read"]
      )

      RemoveFeedFromAction.new.perform(@user.id, @feed_to_remove.id)

      assert_equal [@other_feed.id.to_s], action.reload.feed_ids
    end

    test "marks the action as active when other feeds remain" do
      action = @user.actions.create!(
        title: "test",
        query: "lorem",
        feed_ids: [@feed_to_remove.id.to_s, @other_feed.id.to_s],
        actions: ["mark_read"]
      )

      RemoveFeedFromAction.new.perform(@user.id, @feed_to_remove.id)

      assert action.reload.active?
    end

    test "marks the action as broken when no feeds or tags remain" do
      action = @user.actions.create!(
        title: "test",
        query: "lorem",
        feed_ids: [@feed_to_remove.id.to_s],
        actions: ["mark_read"]
      )

      RemoveFeedFromAction.new.perform(@user.id, @feed_to_remove.id)

      assert action.reload.broken?
    end

    test "is a no-op when the user has no actions" do
      assert_nothing_raised do
        RemoveFeedFromAction.new.perform(@user.id, @feed_to_remove.id)
      end
    end
  end
end
