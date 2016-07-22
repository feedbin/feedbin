require 'test_helper'

class ApplePushNotificationsControllerTest < ActionController::TestCase

  def setup
    @user = users(:ben)
    @token = ActionsController.new().send(:authentication_token, @user)
  end

  test "should create push package" do
    raw_post :create, default_params, {authentication_token: @token}.to_json
    assert_response :success
    assert_equal response.header['Content-Type'], "application/zip"
    assert_equal @user, assigns(:user)
  end

  test "should not create push package with invalid token" do
    assert_raises(ActiveSupport::MessageVerifier::InvalidSignature) do
      raw_post :create, default_params, {authentication_token: "#{@token}s"}.to_json
    end
  end

  test "should destroy device token" do
    set_authorization_header
    patch :update, default_params.merge(device_token: "token")
    assert_difference('Device.count', -1) do
      delete :delete, default_params.merge(device_token: "token")
    end
    assert_response :success
  end

  test "should update device token" do
    set_authorization_header
    assert_difference('Device.count') do
      patch :update, default_params.merge(device_token: "token")
    end
    assert_response :success
  end

  private

  def default_params
    {version: 1, website_push_id: ENV['APPLE_PUSH_WEBSITE_ID']}
  end

  def set_authorization_header
    @request.headers["Authorization"] = "ApplePushNotifications #{@token}"
  end

end
