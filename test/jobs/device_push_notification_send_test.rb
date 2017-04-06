require 'test_helper'

class DevicePushNotificationSendTestTest < ActiveSupport::TestCase
  setup do
    @users = [users(:new), users(:ben)]
    @feeds = create_feeds(@users.first)
    @entries = @users.first.entries

    @devices = @users.map do |user|
      user.devices.create(token: "token#{user.id}", device_type: Device.device_types[:ios])
    end
  end

  test "should send push notification" do
    pool = PushServerMock.new('200')
    user_ids = @users.map(&:id)
    count = Device.where(user_id: user_ids).count
    DevicePushNotificationSend.stub_const(:APNOTIC_POOL, pool) do
      assert_no_difference "Device.count" do
        assert_difference -> {pool.count}, +count do
          DevicePushNotificationSend.new().perform(user_ids, @entries.first.id)
        end
      end
    end
  end

  test "should remove device" do
    pool = PushServerMock.new('410')
    user_ids = @users.map(&:id)
    count = Device.where(user_id: user_ids).count
    DevicePushNotificationSend.stub_const(:APNOTIC_POOL, pool) do
      assert_difference "Device.count", -count do
        DevicePushNotificationSend.new().perform(user_ids, @entries.first.id)
      end
    end
  end

end
