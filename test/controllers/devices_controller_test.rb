require "test_helper"

class DevicesControllerTest < ActionController::TestCase
  setup do
    @user = users(:new)
  end

  test "create creates a browser device for a new endpoint" do
    login_as @user

    assert_difference -> { @user.devices.count }, +1 do
      post :create, params: {device: {data: {endpoint: "https://push.example.com/abc"}}}
    end
    assert_response :ok

    device = @user.devices.last
    assert_equal "https://push.example.com/abc", device.token
    assert_equal "browser", device.device_type
  end

  test "create moves a browser device registered by another account to this one" do
    endpoint = "https://push.example.com/shared-browser-profile"
    users(:ben).devices.create!(token: endpoint, device_type: Device.device_types[:browser])

    login_as @user

    assert_no_difference -> { Device.count } do
      post :create, params: {device: {data: {endpoint: endpoint}}}
    end
    assert_response :ok
    assert_equal @user, Device.find_by(token: endpoint).user
  end

  test "create reuses an existing browser device with the same lowercased token" do
    login_as @user
    @user.devices.create!(token: "https://push.example.com/abc", device_type: Device.device_types[:browser])

    assert_no_difference -> { @user.devices.count } do
      post :create, params: {device: {data: {endpoint: "HTTPS://push.example.com/ABC"}}}
    end
  end
end
