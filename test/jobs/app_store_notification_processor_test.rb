require "test_helper"

class AppStoreNotificationProcessorTest < ActiveSupport::TestCase
  setup do
    @notification = JSON.load File.read(support_file("apple_store_server_notification_v2.json"))
    @user = users(:new)
    @user.authentication_tokens.app.create!(uuid: "49cbb712-cc09-49e7-86c9-697286787ab1")
  end

  test "should create app store notification" do
    StripeMock.start
    assert_difference("AppStoreNotification.count", +1) do
      AppStoreNotificationProcessor.new.perform(@notification["signedPayload"])
    end
    StripeMock.stop
  end
end
