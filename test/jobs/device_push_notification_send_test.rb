require 'test_helper'

class ResponseMock

  def initialize(status, notification)
    @status = status
    @notification = notification
  end

  def status
    @status
  end

  def body
    {"reason" => "BadDeviceToken"}
  end

  def headers
    {"apns-id" => @notification.apns_id}
  end

  def on(event)
    yield self
  end

end

class PoolMock

  attr_reader :status, :count

  def initialize(status)
    @status = status
    @count = 0
  end

  def with
    yield self
  end

  def prepare_push(notification)
    ResponseMock.new(@status, notification)
  end

  def join
    true
  end

  def push_async(notification)
    @count += 1
    true
  end

end

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
    pool = PoolMock.new('200')
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
    pool = PoolMock.new('410')
    user_ids = @users.map(&:id)
    count = Device.where(user_id: user_ids).count
    DevicePushNotificationSend.stub_const(:APNOTIC_POOL, pool) do
      assert_difference "Device.count", -count do
        DevicePushNotificationSend.new().perform(user_ids, @entries.first.id)
      end
    end
  end

end
