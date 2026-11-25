require "test_helper"

class AppStore::ApiTest < ActiveSupport::TestCase
  include StoreSubscriptionHelper

  HISTORY = "https://api.storekit-sandbox.itunes.apple.com/inApps/v1/notifications/history"

  setup do
    key = OpenSSL::PKey::EC.generate("prime256v1")
    @key_file = Tempfile.new(["AuthKey", ".p8"]).tap { _1.write(key.to_pem) }.tap(&:close)
    @environment = {"APPLE_STORE_KEY" => @key_file.path, "APPLE_STORE_KEY_ID" => "KEY123", "APPLE_STORE_ISSUER_ID" => "issuer"}
    @api = AppStore::Api.new(bundle_id: BUNDLE_ID, environment: "sandbox")
  end

  teardown { @key_file.unlink }

  test "it is configured only with all three of the key's parts" do
    with_environment(@environment) { assert AppStore::Api.configured? }
    with_environment(@environment.merge("APPLE_STORE_KEY_ID" => nil)) { assert_not AppStore::Api.configured? }
  end

  test "the notifications Apple sent are read page by page, signed as the app it asks for" do
    first = stub_request(:post, HISTORY).with(body: hash_including("startDate"))
      .to_return(headers: json, body: {notificationHistory: [{signedPayload: "one"}, {signedPayload: "two"}], hasMore: true, paginationToken: "next page"}.to_json)
    second = stub_request(:post, "#{HISTORY}?paginationToken=next+page")
      .to_return(headers: json, body: {notificationHistory: [{signedPayload: "three"}], hasMore: false}.to_json)

    payloads = with_environment(@environment) { @api.notifications(since: 1.hour.ago) }

    assert_equal %w[one two three], payloads
    assert_requested first
    assert_requested second
    assert_requested(:post, HISTORY) do |request|
      claims = JWT.decode(request.headers["Authorization"].delete_prefix("Bearer "), nil, false).first
      claims["bid"] == BUNDLE_ID && claims["iss"] == "issuer" && claims["aud"] == "appstoreconnect-v1"
    end
  end

  test "a subscription's state comes from Apple's last transaction for it" do
    transaction = apple_transaction(id: "7000", expires: 20.days.from_now)
    stub_request(:get, "https://api.storekit-sandbox.itunes.apple.com/inApps/v1/subscriptions/7000").to_return(headers: json, body: {
      data: [{lastTransactions: [{originalTransactionId: "7000", status: 1, signedTransactionInfo: unsigned(transaction), signedRenewalInfo: unsigned(apple_renewal)}]}]
    }.to_json)

    state = with_environment(@environment) { @api.subscription_state("7000") }

    assert_equal :active, state.status
    assert_equal "7000", state.external_id
  end

  test "a transaction Apple doesn't know has no state" do
    stub_request(:get, "https://api.storekit-sandbox.itunes.apple.com/inApps/v1/subscriptions/8000").to_return(status: 404, headers: json, body: {errorCode: 4040010}.to_json)

    assert_nil with_environment(@environment) { @api.subscription_state("8000") }
  end

  test "a key Apple refuses is said to be refused" do
    stub_request(:get, "https://api.storekit-sandbox.itunes.apple.com/inApps/v1/subscriptions/0").to_return(status: 401)
    assert_not with_environment(@environment) { @api.accepted? }

    stub_request(:get, "https://api.storekit-sandbox.itunes.apple.com/inApps/v1/subscriptions/0").to_return(status: 404, headers: json, body: "{}")
    assert with_environment(@environment) { @api.accepted? }
  end

  test "the account token is set on the subscription's transactions" do
    put = stub_request(:put, "https://api.storekit-sandbox.itunes.apple.com/inApps/v1/transactions/7000/appAccountToken")
      .with(body: {appAccountToken: "49cbb712-cc09-49e7-86c9-697286787ab1"}.to_json).to_return(status: 200, body: "")

    with_environment(@environment) { @api.set_app_account_token("7000", "49cbb712-cc09-49e7-86c9-697286787ab1") }

    assert_requested put
  end

  private

  def json = {"Content-Type" => "application/json"}

  def with_environment(values)
    before = values.keys.index_with { ENV[_1] }
    values.each { |key, value| ENV[key] = value }
    yield
  ensure
    before.each { |key, value| ENV[key] = value }
  end
end
