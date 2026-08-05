require "test_helper"

module Search
  class ActionsPerformTest < ActiveSupport::TestCase
    setup do
      Rails.cache.clear
      @user = users(:new)
      @feeds = create_feeds(@user)
      @entries = @user.entries
      @entry = @entries.first
      @action = Action.create(
        user: @user,
        query: @entry.title,
        feed_ids: @feeds.map(&:id),
        actions: ["send_push_notification", "mark_read", "star", "mark_read", "send_ios_notification"]
      )
    end

    test "should send_push_notification" do
      Sidekiq::Worker.clear_all
      assert_difference "WebPushNotificationSend.jobs.size", +1 do
        Throttle.stub :throttle!, true do
          ActionsPerform.new.perform(@entry.id, [@action.id])
        end
      end
    end

    test "should mark_read" do
      assert_difference "UnreadEntry.count", -1 do
        Throttle.stub :throttle!, true do
          ActionsPerform.new.perform(@entry.id, [@action.id])
        end
      end
    end

    test "should star" do
      assert_difference "StarredEntry.count", +1 do
        Throttle.stub :throttle!, true do
          ActionsPerform.new.perform(@entry.id, [@action.id])
        end
      end
    end

    test "should not star past the daily limit" do
      flush_redis
      key = "starred_entries:create:#{@user.id}"
      100.times { Throttle.throttle!(key, 100, 1.day) }
      refute Throttle.throttle!(key, 100, 1.day), "the throttle should already be refusing"

      assert_no_difference "StarredEntry.count" do
        ActionsPerform.new.perform(@entry.id, [@action.id])
      end
    end

    test "should star while under the daily limit" do
      flush_redis

      assert_difference "StarredEntry.count", +1 do
        ActionsPerform.new.perform(@entry.id, [@action.id])
      end
    end

    test "should send_ios_notification" do
      assert_difference "DevicePushNotificationSend.jobs.size", +1 do
        Throttle.stub :throttle!, true do
          ActionsPerform.new.perform(@entry.id, [@action.id])
        end
      end
    end
  end
end