require "test_helper"

class DevicePushNotificationSendTest < ActiveSupport::TestCase
  setup do
    @users = [users(:new), users(:ben)]
    @feeds = create_feeds(@users)
    @entries = @users.first.entries

    @devices = @users.map { |user|
      user.devices.create(token: "token#{user.id}", device_type: Device.device_types[:notifier], application: "com.feedbin.app", data: {"registered_with" => "v3"})
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

  test "pushes under each device's own bundle id" do
    @devices.last.update!(application: "com.feedbin.other")
    pool = PushServerMock.new("200")
    DevicePushNotificationSend.stub_const(:APNOTIC_POOL, pool) do
      DevicePushNotificationSend.new.perform(@users.map(&:id), @entries.first.id, false)
    end

    assert_equal({"token#{@users.first.id}" => "com.feedbin.app", "token#{@users.last.id}" => "com.feedbin.other"}, pool.topics)
  end

  test "a device the retired Notifier registered gets nothing" do
    @devices.first.update!(data: {})
    pool = PushServerMock.new("200")
    DevicePushNotificationSend.stub_const(:APNOTIC_POOL, pool) do
      DevicePushNotificationSend.new.perform(@users.map(&:id), @entries.first.id, false)
    end

    assert_equal ["token#{@users.last.id}"], pool.topics.keys
  end

  test "a suspended account gets nothing" do
    @users.first.update!(suspended: true)
    pool = PushServerMock.new("200")
    DevicePushNotificationSend.stub_const(:APNOTIC_POOL, pool) do
      DevicePushNotificationSend.new.perform(@users.map(&:id), @entries.first.id, false)
    end

    assert_equal ["token#{@users.last.id}"], pool.topics.keys
  end

  test "with no devices it opens no connection" do
    Device.delete_all
    closed = Object.new.tap { |pool| pool.define_singleton_method(:with) { |*| raise "opened a connection" } }
    DevicePushNotificationSend.stub_const(:APNOTIC_POOL, closed) do
      DevicePushNotificationSend.new.perform(@users.map(&:id), @entries.first.id, true)
    end
  end

  test "a device without a bundle id gets nothing" do
    @devices.first.update!(application: nil)
    pool = PushServerMock.new("200")
    DevicePushNotificationSend.stub_const(:APNOTIC_POOL, pool) do
      DevicePushNotificationSend.new.perform(@users.map(&:id), @entries.first.id, false)
    end

    assert_equal ["token#{@users.last.id}"], pool.topics.keys
  end

  test "a token registered under the wrong bundle id is removed" do
    pool = PushServerMock.new("400", reason: "DeviceTokenNotForTopic")
    DevicePushNotificationSend.stub_const(:APNOTIC_POOL, pool) do
      assert_difference "Device.count", -2 do
        DevicePushNotificationSend.new.perform(@users.map(&:id), @entries.first.id, false)
      end
    end
  end

  test "a bundle id the key cannot sign for is reported and the device kept" do
    reported = []
    pool = PushServerMock.new("400", reason: "TopicDisallowed")
    ErrorService.stub(:notify, ->(*args, **kwargs) { reported << (args.first || kwargs) }) do
      DevicePushNotificationSend.stub_const(:APNOTIC_POOL, pool) do
        assert_no_difference "Device.count" do
          DevicePushNotificationSend.new.perform(@users.map(&:id), @entries.first.id, false)
        end
      end
    end

    assert_equal 1, reported.size, "one report per reason and topic, not per device"
    assert_equal 2, reported.first[:parameters][:count]
  end

  test "a token for another app is removed and reported once" do
    reported = []
    pool = PushServerMock.new("400", reason: "DeviceTokenNotForTopic")
    ErrorService.stub(:notify, ->(*args, **kwargs) { reported << (args.first || kwargs) }) do
      DevicePushNotificationSend.stub_const(:APNOTIC_POOL, pool) do
        DevicePushNotificationSend.new.perform(@users.map(&:id), @entries.first.id, false)
      end
    end

    assert_equal 0, Device.count
    assert_equal ["DevicePushNotificationSend#DeviceTokenNotForTopic"], reported.map { _1[:error_class] }
  end

  test "a provider token APNs refuses is reported" do
    reported = []
    pool = PushServerMock.new("403", reason: "InvalidProviderToken")
    ErrorService.stub(:notify, ->(*args, **kwargs) { reported << (args.first || kwargs) }) do
      DevicePushNotificationSend.stub_const(:APNOTIC_POOL, pool) do
        DevicePushNotificationSend.new.perform(@users.map(&:id), @entries.first.id, false)
      end
    end

    assert_equal ["DevicePushNotificationSend#InvalidProviderToken"], reported.map { _1[:error_class] }
  end
end
