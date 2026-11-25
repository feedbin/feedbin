require "test_helper"

class AppStore::SignedPayloadTest < ActiveSupport::TestCase
  include StoreSubscriptionHelper

  test "what Apple signed is read" do
    notification = load_support_json("apple_store_server_notification_v2")
    assert_equal "DID_RENEW", AppStore::SignedPayload.decode(notification["signedPayload"])["notificationType"]
  end

  test "what nobody signed is refused" do
    assert_raises(AppStore::SignedPayload::Invalid) { AppStore::SignedPayload.decode(unsigned(apple_transaction)) }
    assert_raises(AppStore::SignedPayload::Invalid) { AppStore::SignedPayload.decode("nonsense") }
  end

  test "a development server takes Xcode's test store at its word, and nothing else" do
    Rails.stub(:env, ActiveSupport::EnvironmentInquirer.new("development")) do
      assert_equal "Xcode", AppStore::SignedPayload.decode(unsigned(apple_transaction(environment: "Xcode")))["environment"]
      assert_raises(AppStore::SignedPayload::Invalid) { AppStore::SignedPayload.decode(unsigned(apple_transaction(environment: "Sandbox"))) }
    end
    assert_raises(AppStore::SignedPayload::Invalid) { AppStore::SignedPayload.decode(unsigned(apple_transaction(environment: "Xcode"))) }
  end
end
