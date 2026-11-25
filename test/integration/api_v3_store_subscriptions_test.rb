require "test_helper"

class ApiV3StoreSubscriptionsTest < ActionDispatch::IntegrationTest
  include StoreSubscriptionHelper

  setup do
    host! "api.example.com"
    Sidekiq::Worker.clear_all
    start_stripe
    @user = users(:ann)
    @user.update_columns(suspended: true)
    @token = token_for(@user)
    @other = users(:timed)
  end

  teardown { StripeMock.stop }

  test "a lapsed account presents its purchase and is paid for" do
    present apple_transaction(id: "3000", product: "yearly_pro_v1", price: 59990)

    assert_response :success
    body = JSON.parse(response.body)
    assert_equal "account", body["object"]
    assert_equal "app_subscription", body["plan"]["id"]
    assert_equal "active", body["plan"]["status"]
    billing = body["plan"]["billing"]
    assert_equal "apple", billing["source"]
    assert_equal "active", billing["state"]
    assert_equal "yearly", billing["period"]
    assert_equal({"amount" => "59.99", "currency" => "USD"}, billing["price"])
    assert_equal true, billing["renews"]
    assert_equal StoreSubscription.sole.expires_at.utc.iso8601, billing["current_period_ends_at"]
    assert_equal @user, StoreSubscription.sole.user
  end

  test "presenting it tells Apple whose it is and asks Apple for its state" do
    @user.authentication_tokens.app.create!
    present apple_transaction

    assert_equal 1, AppStoreAccountTokenUpdate.jobs.size
    assert_equal 1, StoreSubscriptionRefresh.jobs.size
  end

  test "Apple's signature is checked" do
    notification = load_support_json("apple_store_server_notification_v2")
    signed = AppStore::SignedPayload.read(notification["signedPayload"]).dig("data", "signedTransactionInfo")

    post "/v3/account/store_subscriptions", params: {store: "apple", signed_transaction: signed}.to_json, headers: json
    assert_response :success
    assert StoreSubscription.sole.expired?
    assert_equal "expired", JSON.parse(response.body)["plan"]["billing"]["state"]

    post "/v3/account/store_subscriptions", params: {store: "apple", signed_transaction: unsigned(apple_transaction)}.to_json, headers: json
    assert_response :unprocessable_content
    assert_equal "/signed_transaction", JSON.parse(response.body)["errors"].first["pointer"]
  end

  test "a transaction of some other app is refused" do
    present apple_transaction(bundleId: "com.example.other")

    assert_response :unprocessable_content
    assert_equal 0, StoreSubscription.count
  end

  test "the store and the transaction are required" do
    post "/v3/account/store_subscriptions", params: {store: "amazon", signed_transaction: "x"}.to_json, headers: json
    assert_response :unprocessable_content

    post "/v3/account/store_subscriptions", params: {store: "apple"}.to_json, headers: json
    assert_response :unprocessable_content
  end

  test "events kept for a subscription nobody held become the account's" do
    ErrorService.stub(:notify, nil) do
      AppStoreNotificationProcessor.new.perform(apple_notification("DID_RENEW", id: "4000"))
    end

    present apple_transaction(id: "4000")

    assert_equal @user, AppStoreNotification.sole.user
  end

  test "a subscription live on another account is named, not taken" do
    StoreSubscription.record(apple_state(id: "5000"), user: @other)

    present apple_transaction(id: "5000")

    assert_response :conflict
    body = JSON.parse(response.body)
    assert_equal "store_subscription_owned", body["code"]
    assert_equal "t•••@example.com", body["owner"]["email_hint"]
    assert_equal true, body["movable"]
    assert_equal @other, StoreSubscription.sole.user
    assert @user.reload.suspended
  end

  test "it is moved when the account asks, once in thirty days" do
    StoreSubscription.record(apple_state(id: "5000"), user: @other)

    transfer apple_transaction(id: "5000")

    assert_response :success
    assert_equal "active", JSON.parse(response.body)["plan"]["status"]
    assert_equal @user, StoreSubscription.sole.user
    assert @other.reload.suspended
    assert_includes queued_mail, "store_subscription_moved"

    @token = token_for(@other)
    present apple_transaction(id: "5000")
    assert_response :conflict
    assert_equal false, JSON.parse(response.body)["movable"]
    assert_not_nil JSON.parse(response.body)["movable_at"]

    transfer apple_transaction(id: "5000")
    assert_response :conflict
    assert_equal "store_subscription_moved_recently", JSON.parse(response.body)["code"]
  end

  test "an account paying on the web says so" do
    @token = token_for(users(:ben))

    get "/v3/account", headers: bearer

    billing = JSON.parse(response.body)["plan"]["billing"]
    assert_equal "web", billing["source"]
    assert_equal "monthly", billing["period"]
    assert_equal true, billing["renews"]
  end

  test "the account's token for a purchase is given" do
    token = @user.authentication_tokens.app.create!

    get "/v3/account", headers: bearer

    assert_equal token.reload.uuid, JSON.parse(response.body)["plan"]["billing"]["account_token"]
  end

  test "an account nobody bills says so" do
    get "/v3/account", headers: bearer

    billing = JSON.parse(response.body)["plan"]["billing"]
    assert_nil billing["source"]
    assert_equal false, billing["renews"]
    assert_equal %w[source state product_id period price renews renews_as current_period_ends_at grace_ends_at account_token], billing.keys
  end

  private

  def present(transaction)
    AppStore::SignedPayload.stub(:decode, transaction) do
      post "/v3/account/store_subscriptions", params: {store: "apple", signed_transaction: "signed"}.to_json, headers: json
    end
  end

  def transfer(transaction)
    AppStore::SignedPayload.stub(:decode, transaction) do
      post "/v3/account/store_subscription_transfers", params: {store: "apple", signed_transaction: "signed"}.to_json, headers: json
    end
  end

  def token_for(user)
    user.setting_on!(:api_v3)
    user.oauth_applications.create!(name: "Reader", redirect_uri: "").access_tokens.create!(resource_owner_id: user.id, scopes: "read write account")
  end

  def bearer
    {"Authorization" => "Bearer #{@token.plaintext_token}"}
  end

  def json
    bearer.merge("Content-Type" => "application/json")
  end
end
