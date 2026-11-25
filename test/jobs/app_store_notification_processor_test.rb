require "test_helper"

class AppStoreNotificationProcessorTest < ActiveSupport::TestCase
  include StoreSubscriptionHelper

  TOKEN = "49cbb712-cc09-49e7-86c9-697286787ab1"

  setup do
    Sidekiq::Worker.clear_all
    start_stripe
    @notification = JSON.load File.read(support_file("apple_store_server_notification_v2.json"))
    @user = users(:new)
    @user.authentication_tokens.app.create!(uuid: TOKEN)
    @other = users(:ann)
    @other.authentication_tokens.app.create!(uuid: "5f0a6a52-0e0b-4a55-9d67-0d4f9d9f1c11")
  end

  teardown { StripeMock.stop }

  test "should create app store notification" do
    assert_difference("AppStoreNotification.count", +1) do
      AppStoreNotificationProcessor.new.perform(@notification["signedPayload"])
    end
    assert_equal @user, AppStoreNotification.sole.user
    assert_equal @user, StoreSubscription.sole.user
    assert_equal "sandbox", StoreSubscription.sole.environment
  end

  test "a purchase goes to the account whose token it carries" do
    process "SUBSCRIBED", subtype: "INITIAL_BUY", token: TOKEN

    assert_equal @user, StoreSubscription.sole.user
    assert_equal plans(:app_subscription), @user.reload.plan
    assert_not_nil AppStoreNotification.sole.processed_at
  end

  test "a notification is processed once" do
    payload = apple_notification("SUBSCRIBED", token: TOKEN)
    AppStoreNotificationProcessor.new.perform(payload)
    StoreSubscription.sole.update!(status: :expired)

    AppStoreNotificationProcessor.new.perform(payload)

    assert StoreSubscription.sole.expired?
  end

  test "later news finds the subscription by its transaction, not by a token" do
    process "SUBSCRIBED", token: TOKEN
    @user.authentication_tokens.app.delete_all

    process "EXPIRED", subtype: "VOLUNTARY", token: TOKEN, expires: 1.minute.ago

    assert StoreSubscription.sole.expired?
    assert @user.reload.suspended
    assert_equal [@user.id], AppStoreNotification.pluck(:user_id).uniq
  end

  test "a subscription ending leaves an account that now pays on the web alone" do
    process "SUBSCRIBED", token: TOKEN
    @user.reload.update!(plan: plans(:basic_monthly_3), free_ok: true)

    process "EXPIRED", subtype: "VOLUNTARY", expires: 1.minute.ago

    assert_not @user.reload.suspended
  end

  test "the end of grace lapses the account" do
    process "SUBSCRIBED", token: TOKEN

    process "GRACE_PERIOD_EXPIRED", expires: 16.days.ago, renewal: {isInBillingRetryPeriod: true, gracePeriodExpiresDate: milliseconds(1.minute.ago)}

    assert StoreSubscription.sole.retrying?
    assert @user.reload.suspended
  end

  test "a subscription nobody holds is kept as an event and reported, not raised" do
    reported = []
    ErrorService.stub(:notify, ->(error, *) { reported << error }) do
      assert_no_difference "StoreSubscription.count" do
        process "DID_RENEW"
      end
    end

    assert_nil AppStoreNotification.sole.user
    assert_not_nil AppStoreNotification.sole.processed_at
    assert_equal "1000", reported.sole.dig(:parameters, :original_transaction_id)
  end

  test "another app's notification buys nothing, though Apple signed it and it carries an account's token" do
    payload = JSON.parse(Base64.urlsafe_decode64(apple_notification("SUBSCRIBED", token: TOKEN, bundleId: "com.example.other").split(".")[1]))
    payload["data"]["bundleId"] = "com.example.other"
    reported = []

    ErrorService.stub(:notify, ->(error, *) { reported << error }) do
      AppStoreNotificationProcessor.new.perform(unsigned(payload))
    end

    assert_equal 0, StoreSubscription.count
    assert_equal 0, AppStoreNotification.count
    assert_equal plans(:basic_monthly_3), @user.reload.plan
    assert_equal "com.example.other", reported.sole.dig(:parameters, :bundle_id)
  end

  test "a token that matches no account places nothing" do
    ErrorService.stub(:notify, nil) do
      process "SUBSCRIBED", token: SecureRandom.uuid
      process "DID_RENEW", token: "not-a-uuid"
    end

    assert_equal 0, StoreSubscription.count
    assert_equal 2, AppStoreNotification.count
  end

  test "an account named by hand takes a subscription nobody holds" do
    AppStoreNotificationProcessor.new.perform(apple_notification("DID_RENEW"), @other.id)

    assert_equal @other, StoreSubscription.sole.user
  end

  test "a renewal does not hand a held subscription to the token's account" do
    process "SUBSCRIBED", token: TOKEN

    process "DID_RENEW", token: "5f0a6a52-0e0b-4a55-9d67-0d4f9d9f1c11"

    assert_equal @user, StoreSubscription.sole.user
  end

  test "a lapsed subscription bought again goes to the account that bought it" do
    process "SUBSCRIBED", token: TOKEN
    process "EXPIRED", expires: 1.minute.ago

    process "SUBSCRIBED", subtype: "RESUBSCRIBE", token: "5f0a6a52-0e0b-4a55-9d67-0d4f9d9f1c11"

    assert_equal @other, StoreSubscription.sole.user
    assert_equal plans(:app_subscription), @other.reload.plan
    assert @user.reload.suspended
  end

  test "a deleted account that is charged again is told once" do
    process "SUBSCRIBED", token: TOKEN
    @user.destroy
    Sidekiq::Worker.clear_all

    process "DID_CHANGE_RENEWAL_STATUS", subtype: "AUTO_RENEW_DISABLED"
    assert_empty queued_mail

    process "DID_RENEW"
    process "DID_RENEW"

    assert_equal ["store_still_billing"], queued_mail
    assert_equal 0, StoreSubscription.count
    assert_equal [nil], AppStoreNotification.where(notification_type: "DID_RENEW").pluck(:user_id).uniq
  end

  test "an old charge to a deleted account, processed late, sends nothing" do
    process "SUBSCRIBED", token: TOKEN
    @user.destroy
    Sidekiq::Worker.clear_all

    payload = JSON.parse(Base64.urlsafe_decode64(apple_notification("DID_RENEW").split(".")[1]))
    AppStoreNotificationProcessor.new.perform(unsigned(payload.merge("signedDate" => milliseconds(2.months.ago))))

    assert_empty queued_mail
  end

  test "a notification with no renewal info is taken as it is" do
    process "SUBSCRIBED", token: TOKEN
    process "REFUND", without_renewal: true, revocationDate: milliseconds(Time.now)

    assert StoreSubscription.sole.revoked?
    assert @user.reload.suspended
  end

  test "a notification about no transaction is ignored" do
    payload = unsigned({"notificationType" => "TEST", "notificationUUID" => SecureRandom.uuid, "version" => "2.0", "data" => {"bundleId" => BUNDLE_ID}})

    assert_no_difference "AppStoreNotification.count" do
      AppStoreNotificationProcessor.new.perform(payload)
    end
  end

  private

  def process(type, **options)
    @signed = (@signed || Time.now) + 1.second
    AppStoreNotificationProcessor.new.perform(apple_notification(type, signed: @signed, **options))
  end
end
