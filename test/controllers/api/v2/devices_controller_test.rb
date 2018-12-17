require "test_helper"

class Api::V2::DevicesControllerTest < ApiControllerTestCase
  setup do
    @user = users(:ben)
  end

  test "should create device" do
    api_content_type
    login_as @user

    assert_difference "Device.count", +1 do
      post :create, params: {device: {token: "token", device_type: Device.device_types[:ios], model: "model", application: "application", operating_system: "operating_system"}}, format: :json
      assert_response :success
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
    assert_difference "SafariPushNotificationSend.jobs.size", +1 do
      get :safari_test, format: :json
      assert_response :success
    end
  end
end
