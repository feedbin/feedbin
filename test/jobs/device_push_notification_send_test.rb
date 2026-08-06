require "test_helper"

class DevicePushNotificationSendTest < ActiveSupport::TestCase
  setup do
    @users = [users(:new), users(:ben)]
    @feeds = create_feeds(@users)
    @entries = @users.first.entries

    @devices = @users.map { |user|
      user.devices.create(token: "token#{user.id}", device_type: Device.device_types[:notifier])
    }
  end

  test "should send push notification" do
    pool = PushServerMock.new("200")
    user_ids = @users.map(&:id)
    count = Device.where(user_id: user_ids).count
    DevicePushNotificationSend.stub_const(:APNOTIC_POOL, pool) do
      assert_no_difference "Device.count" do
        assert_difference -> { pool.count }, +count do
          DevicePushNotificationSend.new.perform(user_ids, @entries.first.id, true)
        end
      end
    end
  end

  test "should not send push notification because entry is read" do
    pool = PushServerMock.new("200")
    user_ids = @users.map(&:id)
    count = Device.where(user_id: user_ids).count
    UnreadEntry.delete_all
    DevicePushNotificationSend.stub_const(:APNOTIC_POOL, pool) do
      assert_no_difference "Device.count" do
        assert_no_difference -> { pool.count } do
          DevicePushNotificationSend.new.perform(user_ids, @entries.first.id, true)
        end
      end
    end
  end

  # feed_titles[user_id] || feed_title reads as "this user's title, or the
  # feed's" but the right-hand side is the previous iteration's value, so one
  # subscriber's private rename reaches every later recipient's lock screen.
  test "one recipient's private title does not reach another's notification" do
    entry = @entries.first
    renamer, other = @users
    entry.feed.update!(title: "The Feed's Own Name")
    Subscription.where(user_id: renamer.id, feed_id: entry.feed_id).update_all(title: "PRIVATE-RENAME")
    Subscription.where(user_id: other.id, feed_id: entry.feed_id).update_all(title: nil)

    pool = PushServerMock.new("200")
    DevicePushNotificationSend.stub_const(:APNOTIC_POOL, pool) do
      DevicePushNotificationSend.new.perform([renamer.id, other.id], entry.id, false)
    end

    assert_equal "PRIVATE-RENAME", pool.delivered["token#{renamer.id}"]
    assert_equal entry.feed.title, pool.delivered["token#{other.id}"]
  end

  test "should remove device" do
    pool = PushServerMock.new("410")
    user_ids = @users.map(&:id)
    count = Device.where(user_id: user_ids).count
    DevicePushNotificationSend.stub_const(:APNOTIC_POOL, pool) do
      assert_difference "Device.count", -count do
        DevicePushNotificationSend.new.perform(user_ids, @entries.first.id, true)
      end
    end
  end
end
