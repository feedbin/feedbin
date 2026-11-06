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

  class FakeFirebase
    attr_reader :delivered

    def initialize(*responses)
      @responses = responses
      @delivered = []
    end

    def configured? = true

    def deliver(message)
      @delivered << message
      response = @responses.shift || FirebaseMessaging::Response.new(status: 200, error_code: nil)
      raise response if response.is_a?(Exception)
      response
    end
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
    assert_equal "Episode content", notification.alert[:body]
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

  test "sends Android devices a Firebase data message and keeps them away from APNs" do
    @device.destroy
    @user.devices.create!(token: "fcm-token", device_type: Device.device_types[:podcast_android])
    pool = SyncPushPool.new(status: "200")
    firebase = FakeFirebase.new

    DevicePushNotificationSend.stub_const(:APNOTIC_POOL, pool) do
      PodcastPushNotification.stub_const(:FIREBASE, firebase) do
        PodcastPushNotification.new.perform(@user.id, @entry.id)
      end
    end

    assert_equal 0, pool.pushed.size
    assert_equal 1, firebase.delivered.size
    message = firebase.delivered.first
    assert_equal "fcm-token", message[:token]
    assert_equal "high", message.dig(:android, :priority)
    assert_equal(
      {
        feed_id: @feed.id.to_s,
        entry_id: @entry.id.to_s,
        title: "Episode 1",
        subtitle: @feed.title,
        body: "A short subtitle",
        image_url: "http://example.com/episode.jpg"
      },
      message[:data]
    )
    assert message[:data].values.all?(String)
  end

  test "pushes to iOS and Android devices of the same user" do
    @user.devices.create!(token: "fcm-token", device_type: Device.device_types[:podcast_android])
    pool = SyncPushPool.new(status: "200")
    firebase = FakeFirebase.new

    DevicePushNotificationSend.stub_const(:APNOTIC_POOL, pool) do
      PodcastPushNotification.stub_const(:FIREBASE, firebase) do
        PodcastPushNotification.new.perform(@user.id, @entry.id)
      end
    end

    assert_equal ["podcast-token"], pool.pushed.map(&:token)
    assert_equal ["fcm-token"], firebase.delivered.map { |message| message[:token] }
  end

  test "skips inactive Android devices" do
    @user.devices.create!(token: "fcm-token", device_type: Device.device_types[:podcast_android], active: false)
    firebase = FakeFirebase.new

    DevicePushNotificationSend.stub_const(:APNOTIC_POOL, SyncPushPool.new(status: "200")) do
      PodcastPushNotification.stub_const(:FIREBASE, firebase) do
        PodcastPushNotification.new.perform(@user.id, @entry.id)
      end
    end

    assert_empty firebase.delivered
  end

  test "removes an Android device whose token Firebase reports unregistered" do
    @device.destroy
    @user.devices.create!(token: "fcm-token", device_type: Device.device_types[:podcast_android])
    firebase = FakeFirebase.new(FirebaseMessaging::Response.new(status: 404, error_code: "UNREGISTERED"))

    assert_difference "Device.count", -1 do
      PodcastPushNotification.stub_const(:FIREBASE, firebase) do
        PodcastPushNotification.new.perform(@user.id, @entry.id)
      end
    end
  end

  test "a failed Firebase send leaves the device and still reaches the user's other devices" do
    @device.destroy
    @user.devices.create!(token: "fcm-1", device_type: Device.device_types[:podcast_android])
    @user.devices.create!(token: "fcm-2", device_type: Device.device_types[:podcast_android])
    firebase = FakeFirebase.new(FirebaseMessaging::Error.new("token request failed"))

    assert_no_difference "Device.count" do
      PodcastPushNotification.stub_const(:FIREBASE, firebase) do
        PodcastPushNotification.new.perform(@user.id, @entry.id)
      end
    end
    assert_equal 2, firebase.delivered.size
  end

  test "skips Android devices when Firebase isn't configured" do
    @device.destroy
    @user.devices.create!(token: "fcm-token", device_type: Device.device_types[:podcast_android])
    firebase = FakeFirebase.new
    firebase.define_singleton_method(:configured?) { false }

    PodcastPushNotification.stub_const(:FIREBASE, firebase) do
      PodcastPushNotification.new.perform(@user.id, @entry.id)
    end

    assert_empty firebase.delivered
  end
end
