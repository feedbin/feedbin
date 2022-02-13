require "test_helper"

class AppStore::NotificationsV2ControllerTest < ActionController::TestCase
  setup do
    Sidekiq::Worker.clear_all
    @notification = JSON.load File.read(support_file("apple_store_server_notification_v2.json"))
  end

  test "should schedule processing job" do
    assert_difference "Sidekiq::Queues['critical'].count", +1 do
      post :create, params: @notification, as: :json, format: :json
    end
    assert_response :success
  end

  test "should not schedule processing job" do
    assert_no_difference "Sidekiq::Queues['critical'].count" do
      post :create, params: {signedPayload: "asdf"}, as: :json, format: :json
    end
    assert_response :not_found
  end
end
