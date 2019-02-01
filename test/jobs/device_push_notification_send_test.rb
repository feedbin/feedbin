require "test_helper"

class DevicePushNotificationSendTest < ActiveSupport::TestCase
  setup do
    @users = [users(:new), users(:ben)]
    @feeds = create_feeds(@users)
    @entries = @users.first.entries

    @devices = @users.map { |user|
      user.devices.create(token: "token#{user.id}", device_type: Device.device_types[:ios])
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
