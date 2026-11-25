require "test_helper"

class StoreSubscriptionTest < ActiveSupport::TestCase
  include StoreSubscriptionHelper

  setup do
    Sidekiq::Worker.clear_all
    start_stripe
    @trial = users(:ann)
    @trial.update_columns(suspended: true)
    @other = users(:timed)
  end

  teardown { StripeMock.stop }

  test "a subscription presented by an account pays for it" do
    subscription = StoreSubscription.record(apple_state, user: @trial)

    assert subscription.active?
    assert_equal @trial, subscription.user
    assert_equal "monthly", subscription.period
    assert_in_delta 5.99, subscription.price
    assert_equal plans(:app_subscription), @trial.reload.plan
    assert_not @trial.suspended
  end

  test "news of a subscription nobody holds makes no subscription" do
    assert_no_difference "StoreSubscription.count" do
      assert_nil StoreSubscription.record(apple_state)
    end
  end

  test "an account is always required" do
    assert_raises(ActiveRecord::NotNullViolation) do
      StoreSubscription.new(store: :apple, external_id: "1", app_identifier: "a", environment: "production", product_id: "p", status: :active).save(validate: false)
    end
  end

  test "its ending lapses the account it paid for" do
    StoreSubscription.record(apple_state, user: @trial)
    StoreSubscription.record(apple_state(expires: 1.minute.ago, ended: true))

    assert StoreSubscription.sole.expired?
    assert @trial.reload.suspended
  end

  test "its ending leaves an account that now pays on the web alone" do
    StoreSubscription.record(apple_state, user: @trial)
    @trial.update!(plan: plans(:basic_monthly_3), free_ok: true)

    StoreSubscription.record(apple_state(expires: 1.minute.ago, ended: true))

    assert_not @trial.reload.suspended
    assert_equal plans(:basic_monthly_3), @trial.plan
  end

  test "an account paying on the web moves to the store's plan, so it pays once" do
    paying = users(:ben)
    StoreSubscription.record(apple_state, user: paying)

    assert_equal plans(:app_subscription), paying.reload.plan
  end

  test "an account that pays nothing keeps its plan" do
    @trial.update_columns(plan_id: plans(:free).id, suspended: false)
    StoreSubscription.record(apple_state, user: @trial)

    assert_equal plans(:free), @trial.reload.plan
  end

  test "grace keeps service and flags the payment" do
    StoreSubscription.record(apple_state, user: @trial)
    StoreSubscription.record(apple_state(expires: 1.minute.ago, renewal: {gracePeriodExpiresDate: milliseconds(10.days.from_now), isInBillingRetryPeriod: true}))

    assert StoreSubscription.sole.grace?
    assert_not @trial.reload.suspended
    assert @trial.billing_issue?
  end

  test "the end of grace lapses the account while the store keeps trying" do
    StoreSubscription.record(apple_state, user: @trial)
    StoreSubscription.record(apple_state(expires: 1.day.ago, ended: true, renewal: {gracePeriodExpiresDate: milliseconds(1.minute.ago), isInBillingRetryPeriod: true}))

    assert StoreSubscription.sole.retrying?
    assert @trial.reload.suspended
  end

  test "a refund ends it" do
    StoreSubscription.record(apple_state, user: @trial)
    StoreSubscription.record(apple_state(revocationDate: milliseconds(Time.now)))

    assert StoreSubscription.sole.revoked?
    assert @trial.reload.suspended
  end

  test "Apple's own status wins over the dates" do
    assert_equal :retrying, apple_state(status: 3).status
    assert_equal :grace, apple_state(expires: 1.day.ago, status: 4).status
  end

  test "older news is ignored" do
    StoreSubscription.record(apple_state(signed: Time.now), user: @trial)
    StoreSubscription.record(apple_state(expires: 1.day.ago, signed: 1.hour.ago, ended: true))

    assert StoreSubscription.sole.active?
  end

  test "a live subscription is not another account's to present" do
    StoreSubscription.record(apple_state, user: @trial)

    error = assert_raises(StoreSubscription::OwnedByAnotherAccount) do
      StoreSubscription.record(apple_state, user: @other)
    end
    assert_equal @trial, error.subscription.user
  end

  test "a lapsed subscription goes to the account that buys it again" do
    StoreSubscription.record(apple_state, user: @trial)
    StoreSubscription.record(apple_state(expires: 1.minute.ago, ended: true))

    StoreSubscription.record(apple_state(expires: 1.month.from_now), user: @other)

    assert_equal @other, StoreSubscription.sole.user
    assert_equal plans(:app_subscription), @other.reload.plan
    assert @trial.reload.suspended
  end

  test "a lapsed subscription stays where it is when another account only shows it" do
    StoreSubscription.record(apple_state, user: @trial)
    StoreSubscription.record(apple_state(expires: 1.minute.ago, ended: true))

    StoreSubscription.record(apple_state(expires: 1.minute.ago, ended: true), user: @other)

    assert_equal @trial, StoreSubscription.sole.user
  end

  test "moving it pays for the new account, lapses the old one and writes to it" do
    subscription = StoreSubscription.record(apple_state, user: @trial)

    subscription.move_to(@other)

    assert_equal ["store_subscription_moved"], queued_mail
    assert_equal @other, subscription.reload.user
    assert_equal plans(:app_subscription), @other.reload.plan
    assert @trial.reload.suspended
    assert_equal 1, AppStoreAccountTokenUpdate.jobs.size
  end

  test "it moves once in thirty days" do
    subscription = StoreSubscription.record(apple_state, user: @trial)
    subscription.move_to(@other)

    assert_raises(StoreSubscription::MovedTooRecently) { subscription.move_to(@trial) }

    travel 31.days do
      subscription.move_to(@trial)
      assert_equal @trial, subscription.reload.user
    end
  end

  test "a deleted account keeps a note of what still bills it" do
    StoreSubscription.record(apple_state(id: "2000"), user: @trial)

    @trial.destroy

    assert_equal 0, StoreSubscription.count
    assert_equal [{"store" => "apple", "external_id" => "2000", "product_id" => "monthly_pro_v1"}], DeletedUser.holding(:apple, "2000").sole.store_subscriptions
  end
end
