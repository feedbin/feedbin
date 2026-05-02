require "test_helper"

class PodcastPushNotificationTest < ActiveSupport::TestCase
  class SyncPushPool
    attr_reader :pushed

    def initialize(status:, body: {})
      @status = status
      @body = body
      @pushed = []
    end

    def with
      yield self
    end

    def push(notification)
      @pushed << notification
      Response.new(@status, @body)
    end

    Response = Struct.new(:status, :body)
  end

  setup do
    @user = users(:new)
    @feed = create_feeds(@user, 1).first
    @feed.update!(options: {"itunes_image" => "http://example.com/feed.jpg"})
    @entry = @feed.entries.create!(
      title: "Episode 1",
      url: "http://example.com/ep",
      public_id: SecureRandom.hex,
      content: "Episode content",
      data: {
        "itunes_subtitle" => "A short subtitle",
        "itunes_summary"  => "A much longer summary that exceeds the subtitle length significantly",
        "itunes_image"    => "http://example.com/episode.jpg"
      }
    )
    @device = @user.devices.create!(token: "podcast-token", device_type: Device.device_types[:podcast])
  end

  test "pushes a notification for each podcast device of the user" do
    pool = SyncPushPool.new(status: "200")

    DevicePushNotificationSend.stub_const(:APNOTIC_POOL, pool) do
      PodcastPushNotification.new.perform(@user.id, @entry.id)
    end

    assert_equal 1, pool.pushed.size
    notification = pool.pushed.first
    assert_equal "Episode 1", notification.alert[:title]
    assert_equal @feed.title, notification.alert[:subtitle]
    assert_equal "A short subtitle", notification.alert[:body]
    assert_equal @entry.feed_id, notification.thread_id
  end

  test "skips inactive devices and devices of other types" do
    @device.update!(active: false)
    notifier_device = @user.devices.create!(token: "notifier-token", device_type: Device.device_types[:notifier])
    pool = SyncPushPool.new(status: "200")

    DevicePushNotificationSend.stub_const(:APNOTIC_POOL, pool) do
      PodcastPushNotification.new.perform(@user.id, @entry.id)
    end

    assert_equal 0, pool.pushed.size
  end

  test "removes the device when APNS responds with 410" do
    pool = SyncPushPool.new(status: "410")

    assert_difference "Device.count", -1 do
      DevicePushNotificationSend.stub_const(:APNOTIC_POOL, pool) do
        PodcastPushNotification.new.perform(@user.id, @entry.id)
      end
    end
  end

  test "removes the device when APNS responds 400 BadDeviceToken" do
    pool = SyncPushPool.new(status: "400", body: {"reason" => "BadDeviceToken"})

    assert_difference "Device.count", -1 do
      DevicePushNotificationSend.stub_const(:APNOTIC_POOL, pool) do
        PodcastPushNotification.new.perform(@user.id, @entry.id)
      end
    end
  end

  test "leaves the device alone when APNS responds with another 400 reason" do
    pool = SyncPushPool.new(status: "400", body: {"reason" => "PayloadTooLarge"})

    assert_no_difference "Device.count" do
      DevicePushNotificationSend.stub_const(:APNOTIC_POOL, pool) do
        PodcastPushNotification.new.perform(@user.id, @entry.id)
      end
    end
  end

  test "uses entry summary when itunes_subtitle and itunes_summary are missing" do
    @entry.update!(data: {})
    pool = SyncPushPool.new(status: "200")

    DevicePushNotificationSend.stub_const(:APNOTIC_POOL, pool) do
      PodcastPushNotification.new.perform(@user.id, @entry.id)
    end

    notification = pool.pushed.first
    assert_kind_of String, notification.alert[:body]
  end

  test "uses the only itunes summary option when subtitle is missing" do
    @entry.update!(data: {"itunes_summary" => "Only summary present"})
    pool = SyncPushPool.new(status: "200")

    DevicePushNotificationSend.stub_const(:APNOTIC_POOL, pool) do
      PodcastPushNotification.new.perform(@user.id, @entry.id)
    end

    notification = pool.pushed.first
    assert_equal "Only summary present", notification.alert[:body]
  end
end
