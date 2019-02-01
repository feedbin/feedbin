require "test_helper"

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
      actions: ["send_push_notification", "mark_read", "star", "mark_read", "send_ios_notification"],
    )
  end

  test "should send_push_notification" do
    Sidekiq::Worker.clear_all
    assert_difference "SafariPushNotificationSend.jobs.size", +1 do
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

  test "should send_ios_notification" do
    assert_difference "DevicePushNotificationSend.jobs.size", +1 do
      Throttle.stub :throttle!, true do
        ActionsPerform.new.perform(@entry.id, [@action.id])
      end
    end
  end
end
