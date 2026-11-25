require "test_helper"

class StoreSubscription::BackfillTest < ActiveSupport::TestCase
  include StoreSubscriptionHelper

  setup do
    start_stripe
    @user = users(:ann)
    @user.update_columns(plan_id: plans(:app_subscription).id, suspended: false)
  end

  teardown { StripeMock.stop }

  test "makes a subscription from the latest notification, for the account it was credited to" do
    notify @user.id, "SUBSCRIBED", id: "1000", signed: 2.days.ago
    notify @user.id, "DID_RENEW", id: "1000", signed: 1.day.ago, expires: 20.days.from_now

    result = StoreSubscription::Backfill.new.run

    assert_equal 1, result.created
    assert StoreSubscription.sole.active?
    assert_equal @user, StoreSubscription.sole.user
    assert_empty result.would_lapse

    assert_equal 0, StoreSubscription::Backfill.new.run.created
  end

  test "says who would lapse, and lapses them only when applying" do
    notify @user.id, "DID_RENEW", id: "1000", expires: 3.months.ago

    result = StoreSubscription::Backfill.new.run
    assert_equal [@user.id], result.would_lapse
    assert_not @user.reload.suspended

    StoreSubscription.delete_all
    StoreSubscription::Backfill.new(apply: true).run
    assert @user.reload.suspended
  end

  test "a subscription whose account is gone is noted on the deleted user, and only while it bills" do
    deleted = DeletedUser.create!(email: "gone@example.com", original_user_id: 999_001)
    notify 999_001, "DID_RENEW", id: "2000", expires: 20.days.from_now
    notify 999_001, "EXPIRED", id: "3000", expires: 3.months.ago
    notify 999_002, "DID_RENEW", id: "4000", expires: 20.days.from_now

    result = StoreSubscription::Backfill.new.run

    assert_equal 0, StoreSubscription.count
    assert_equal 1, result.noted_on_deleted_users
    assert_equal 1, result.without_an_account
    assert_equal ["2000"], deleted.reload.store_subscriptions.map { _1["external_id"] }
  end

  test "Apple is asked about one not known to have ended" do
    notify @user.id, "DID_RENEW", id: "1000", expires: 3.months.ago
    asked = apple_state(id: "1000", expires: 9.months.from_now, status: 1)
    api = Minitest::Mock.new
    api.expect(:subscription_state, asked, ["1000"])

    AppStore::Api.stub(:new, api) do
      StoreSubscription::Backfill.new(ask_apple: true).run
    end

    assert StoreSubscription.sole.active?
    api.verify
  end

  private

  def notify(user_id, type, id:, signed: Time.now, **transaction)
    AppStoreNotification.create!(
      user_id: user_id, original_transaction_id: id, notification_id: SecureRandom.uuid, notification_type: type, version: "2.0",
      data: {"notificationType" => type, "signedDate" => milliseconds(signed), "data" => {
        "bundleId" => BUNDLE_ID, "environment" => "Production",
        "signedTransactionInfo" => apple_transaction(id: id, signed: signed, **transaction),
        "signedRenewalInfo" => apple_renewal(signed: signed)
      }}
    )
  end
end
