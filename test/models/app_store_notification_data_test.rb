require "test_helper"
require "base64"

class AppStoreNotificationDataTest < ActiveSupport::TestCase
  def encode_part(hash)
    Base64.urlsafe_encode64(JSON.dump(hash))
  end

  def fake_jwt(payload)
    "header.#{encode_part(payload)}.sig"
  end

  def make_notification(transaction: {}, renewal: {})
    fake_jwt(
      "data" => {
        "signedTransactionInfo" => fake_jwt(transaction),
        "signedRenewalInfo" => fake_jwt(renewal)
      }
    )
  end

  setup do
    @transaction = {
      "originalTransactionId" => "tx-1234",
      "appAccountToken" => "acct-token",
      "productId" => "monthly_pro_v1"
    }
    @renewal = {"autoRenewProductId" => "monthly_pro_v1"}
    @notification = make_notification(transaction: @transaction, renewal: @renewal)
  end

  test "data decodes the outer payload and the embedded signed JWTs" do
    obj = AppStoreNotificationData.new(@notification)
    decoded = obj.data
    assert_equal @transaction, decoded["data"]["signedTransactionInfo"]
    assert_equal @renewal, decoded["data"]["signedRenewalInfo"]
  end

  test "data is memoized across calls" do
    obj = AppStoreNotificationData.new(@notification)
    first = obj.data
    second = obj.data
    assert_same first, second
  end

  test "original_transaction_id reads from the decoded transaction info" do
    obj = AppStoreNotificationData.new(@notification)
    assert_equal "tx-1234", obj.original_transaction_id
  end

  test "app_account_token reads from the decoded transaction info" do
    obj = AppStoreNotificationData.new(@notification)
    assert_equal "acct-token", obj.app_account_token
  end

  test "product_id reads from the decoded transaction info" do
    obj = AppStoreNotificationData.new(@notification)
    assert_equal "monthly_pro_v1", obj.product_id
  end

  test "format_date converts a Time to milliseconds since epoch" do
    t = Time.utc(2024, 1, 1)
    assert_equal t.to_i * 1_000, AppStoreNotificationData.send(:format_date, t)
  end

  test "most_recent_possible_start returns the API min date when 180 days back is earlier" do
    travel_to Time.utc(2022, 7, 1) do
      result = AppStoreNotificationData.send(:most_recent_possible_start)
      assert_equal Time.parse("2022-06-06"), result
    end
  end

  test "most_recent_possible_start returns 180-days-ago after the API min date" do
    travel_to Time.utc(2030, 1, 1) do
      result = AppStoreNotificationData.send(:most_recent_possible_start)
      expected = Time.now - 180.days
      assert_in_delta expected, result, 1
    end
  end

  test "from_notification_history POSTs to Apple and wraps the payloads" do
    AppStoreNotificationData.stub :token, "tk" do
      stub_request(:post, "https://api.storekit.itunes.apple.com/inApps/v1/notifications/history")
        .to_return(status: 200, body: {
          "notificationHistory" => [
            {"signedPayload" => @notification},
            {"signedPayload" => @notification}
          ]
        }.to_json, headers: {"Content-Type" => "application/json"})

      results = AppStoreNotificationData.from_notification_history
      assert_equal 2, results.size
      assert_kind_of AppStoreNotificationData, results.first
      assert_equal "tx-1234", results.first.original_transaction_id
    end
  end

  test "from_notification_history accepts explicit start_date and end_date" do
    AppStoreNotificationData.stub :token, "tk" do
      captured_body = nil
      stub_request(:post, "https://api.storekit.itunes.apple.com/inApps/v1/notifications/history")
        .with { |req| captured_body = JSON.parse(req.body); true }
        .to_return(status: 200, body: '{"notificationHistory":[]}', headers: {"Content-Type" => "application/json"})

      start_date = Time.utc(2030, 1, 1)
      end_date = Time.utc(2030, 6, 1)
      AppStoreNotificationData.from_notification_history(start_date: start_date, end_date: end_date)

      assert_equal start_date.to_i * 1000, captured_body["startDate"]
      assert_equal end_date.to_i * 1000, captured_body["endDate"]
    end
  end

  test "from_order_id resolves originalTransactionId then queries history" do
    AppStoreNotificationData.stub :token, "tk" do
      stub_request(:get, "https://api.storekit.itunes.apple.com/inApps/v1/lookup/order-1")
        .to_return(status: 200, body: {"signedTransactions" => ["dont.care.signature"]}.to_json,
          headers: {"Content-Type" => "application/json"})

      captured_body = nil
      stub_request(:post, "https://api.storekit.itunes.apple.com/inApps/v1/notifications/history")
        .with { |req| captured_body = JSON.parse(req.body); true }
        .to_return(status: 200, body: {"notificationHistory" => [{"signedPayload" => @notification}]}.to_json,
          headers: {"Content-Type" => "application/json"})

      JWT.stub :decode, [{"originalTransactionId" => "tx-9999"}, {}] do
        results = AppStoreNotificationData.from_order_id("order-1")
        assert_equal 1, results.size
      end
      assert_equal "tx-9999", captured_body["originalTransactionId"]
    end
  end

  test "apps GETs the App Store Connect apps endpoint" do
    AppStoreNotificationData.stub :token, "tk" do
      stub = stub_request(:get, "https://api.appstoreconnect.apple.com/v1/apps")
        .to_return(status: 200, body: '{"data":[{"id":"a1"}]}', headers: {"Content-Type" => "application/json"})
      response = AppStoreNotificationData.apps
      assert_requested stub
      assert_equal "a1", response["data"].first["id"]
    end
  end
end
