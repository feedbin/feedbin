require "test_helper"

class AppStore::NotificationsV2ControllerTest < ActionController::TestCase
  setup do
    Sidekiq::Worker.clear_all
    @notification = load_support_json("apple_store_server_notification_v2")
  end

  test "should schedule processing job" do
    assert_difference -> { AppStoreNotificationProcessor.jobs.size }, +1 do
      post :create, params: @notification, as: :json, format: :json
    end
    assert_response :success
  end

  test "should not schedule processing job" do
    assert_no_difference -> { AppStoreNotificationProcessor.jobs.size } do
      post :create, params: {signedPayload: "asdf"}, as: :json, format: :json
    end
    assert_response :bad_request
  end

  test "should reject a hand-built payload whose header has no x5c" do
    header = Base64.urlsafe_encode64({"alg" => "ES256"}.to_json, padding: false)
    claims = Base64.urlsafe_encode64({}.to_json, padding: false)

    assert_no_difference -> { AppStoreNotificationProcessor.jobs.size } do
      post :create, params: {signedPayload: "#{header}.#{claims}.signature"}, as: :json, format: :json
    end
    assert_response :bad_request
  end
end
