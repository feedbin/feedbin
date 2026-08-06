require "test_helper"

class Api::V2::DevicesControllerTest < ApiControllerTestCase
  setup do
    @user = users(:ben)
  end

  test "should create device" do
    api_content_type
    login_as @user

    assert_difference "Device.count", +1 do
      post :create, params: {device: {token: "token", device_type: Device.device_types[:notifier], model: "model", application: "application", operating_system: "operating_system"}}, format: :json
      assert_response :success
    end
  end

  test "should move a device registered by another account to this one" do
    token = "https://push.example.com/shared-browser-profile"
    users(:new).devices.create!(token: token, device_type: Device.device_types[:notifier])

    api_content_type
    login_as @user

    assert_no_difference "Device.count" do
      post :create, params: {device: {token: token, device_type: Device.device_types[:notifier]}}, format: :json
    end
    assert_response :success
    assert_equal @user, Device.find_by(token: token).user
  end

  test "should update the device when the token differs only in case" do
    token = "https://push.example.com/AbC"
    @user.devices.create!(token: token, device_type: Device.device_types[:notifier], model: "old")

    api_content_type
    login_as @user

    assert_no_difference "Device.count" do
      post :create, params: {device: {token: token.downcase, device_type: Device.device_types[:notifier], model: "new"}}, format: :json
    end
    assert_response :success
    assert_equal "new", @user.devices.first.model
  end

  test "should recover when a concurrent registration of the same token wins" do
    token = "https://push.example.com/raced"
    @committed_token = token
    other_user_id = users(:new).id

    api_content_type
    login_as @user

    outside_transaction do |other_request|
      raced = false
      race_winner = ->(_record) do
        next if raced
        raced = true
        other_request.execute(<<~SQL, other_user_id, token)
          INSERT INTO devices (user_id, token, device_type, created_at, updated_at)
          VALUES (?, ?, 0, now(), now())
        SQL
      end
      Device.set_callback(:create, :before, race_winner)

      begin
        post :create, params: {device: {token: token, device_type: Device.device_types[:notifier], model: "phone"}}, format: :json
        assert_response :success
        assert raced, "the race was never triggered"

        device = Device.find_by(token: token)
        assert_equal @user, device.user, "the losing registration should still take the device"
        assert_equal "phone", device.model
      ensure
        Device.skip_callback(:create, :before, race_winner)
      end
    end
  end

  def after_teardown
    super
    return unless @committed_token
    outside_transaction do |connection|
      connection.execute("DELETE FROM devices WHERE token = ?", @committed_token)
    end
  end

  test "should get ios_test" do
    Sidekiq::Worker.clear_all
    login_as @user
    @user.feeds.first.entries.create!(url: "url", public_id: "new")
    assert_difference "DevicePushNotificationSend.jobs.size", +1 do
      get :ios_test, format: :json
      assert_response :success
    end
  end

  test "should get safari_test" do
    Sidekiq::Worker.clear_all
    login_as @user
    @user.feeds.first.entries.create!(url: "url", public_id: "new")
    assert_difference "WebPushNotificationSend.jobs.size", +1 do
      get :safari_test, format: :json
      assert_response :success
    end
  end
end
