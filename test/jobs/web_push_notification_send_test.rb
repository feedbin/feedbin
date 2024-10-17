require "test_helper"

class WebPushNotificationSendTest < ActiveSupport::TestCase
  setup do
    @users = [users(:new), users(:ben)]
    @feeds = create_feeds(@users.first)
    @entries = @users.first.entries
  end

  test "should send push notification" do
    @devices = @users.map { |user|
      user.devices.create(token: "token#{user.id}", device_type: Device.device_types[:safari])
    }

    pool = PushServerMock.new("200")
    user_ids = @users.map(&:id)
    count = Device.where(user_id: user_ids).count
    WebPushNotificationSend.stub_const(:APNOTIC_POOL, pool) do
      assert_no_difference "Device.count" do
        assert_difference -> { pool.count }, +count do
          WebPushNotificationSend.new.perform(user_ids, @entries.first.id, false)
        end
      end
    end
  end

  test "should remove safari device" do
    @devices = @users.map { |user|
      user.devices.create(token: "token#{user.id}", device_type: Device.device_types[:safari])
    }

    pool = PushServerMock.new("410")
    user_ids = @users.map(&:id)
    count = Device.where(user_id: user_ids).count
    WebPushNotificationSend.stub_const(:APNOTIC_POOL, pool) do
      assert_difference "Device.count", -count do
        WebPushNotificationSend.new.perform(user_ids, @entries.first.id, false)
      end
    end
  end

  test "should remove web device" do
    stub_request(:post, %r{example.com}).to_return(status: 410)

    # from https://github.com/pushpad/web-push/blob/master/spec/spec_helper.rb
    Feedbin::Application.config.vapid_key = WebPush::VapidKey.from_keys('BB37UCyc8LLX4PNQSe-04vSFvpUWGrENubUaslVFM_l5TxcGVMY0C3RXPeUJAQHKYlcOM2P4vTYmkoo0VZGZTM4=', 'OPrw1Sum3gRoL4-DXfSCC266r-qfFSRZrnj8MgIhRHg=')

    @devices = @users.map { |user|
      user.devices.create(
        token: "token#{user.id}",
        device_type: Device.device_types[:browser],
        data: {
          endpoint: 'https://example.com',
          keys: {
            p256dh: 'BN4GvZtEZiZuqFxSKVZfSfluwKBD7UxHNBmWkfiZfCtgDE8Bwh-_MtLXbBxTBAWH9r7IPKL0lhdcaqtL1dfxU5E=',
            auth: 'Q2BoAjC09xH3ywDLNJr-dA==',
          }
        }
      )
    }

    user_ids = @users.map(&:id)
    count = Device.where(user_id: user_ids).count
    assert_difference -> {Device.count}, -count do
      WebPushNotificationSend.new.perform(user_ids, @entries.first.id, false)
    end
  end
end
