class AppStoreNotificationData

  attr_reader :notification

  def initialize(notification)
    @notification = notification
  end

  def self.from_notification_history(start_date: nil, end_date: nil)
    body = {}

    start_date = start_date || most_recent_possible_start
    body[:startDate] = format_date(start_date)

    end_date = end_date || Time.now
    body[:endDate] = format_date(end_date)

    response = HTTP
      .auth("Bearer %<token>s" % {token: token})
      .post("https://api.storekit.itunes.apple.com/inApps/v1/notifications/history", json: body)
      .parse

    response["notificationHistory"].map do |item|
      new(item["signedPayload"])
    end
  end

  def self.from_order_id(order_id)
    response = HTTP
      .auth("Bearer %<token>s" % {token: token})
      .get("https://api.storekit.itunes.apple.com/inApps/v1/lookup/%<order_id>s" % {order_id: order_id})
      .parse

    original_transaction_id = JWT
      .decode(response["signedTransactions"].first, nil, false, algorithm: "ES256")
      .first
      .safe_dig("originalTransactionId")

    body = {
      startDate: format_date(most_recent_possible_start),
      endDate: format_date(Time.now),
      originalTransactionId: original_transaction_id
    }

    response = HTTP
      .auth("Bearer %<token>s" % {token: token})
      .post("https://api.storekit.itunes.apple.com/inApps/v1/notifications/history", json: body)
      .parse

    response["notificationHistory"].map do |item|
      new(item["signedPayload"])
    end
  end

  def self.apps
    response = HTTP
      .auth("Bearer %<token>s" % {token: token})
      .get("https://api.appstoreconnect.apple.com/v1/apps")
      .parse
  end

  def data
    @data ||= begin
      decode(@notification).tap do |hash|
        hash["data"]["signedTransactionInfo"] = decode(hash["data"]["signedTransactionInfo"])
        hash["data"]["signedRenewalInfo"] = decode(hash["data"]["signedRenewalInfo"])
      end
    end
  end

  def original_transaction_id
    data.safe_dig("data", "signedTransactionInfo", "originalTransactionId")
  end

  def app_account_token
    data.safe_dig("data", "signedTransactionInfo", "appAccountToken")
  end

  def product_id
    data.safe_dig("data", "signedTransactionInfo", "productId")
  end

  private

  def decode(data)
    _, payload, _ = data.split(".")
    JSON.load(Base64.decode64(payload))
  end

  def self.format_date(date)
    date.to_i * 1_000
  end

  def self.most_recent_possible_start
    # can be either 180 days or when the API became available 2022-06-06
    [Time.now - 180.days, Time.parse("2022-06-06")].max
  end

  def self.token
    key = OpenSSL::PKey.read(File.read(ENV["APPLE_STORE_KEY"]))
    headers = {
      alg: "ES256",
      kid: ENV["APPLE_STORE_KEY_ID"],
      typ: "JWT"
    }
    payload = {
      iss: ENV["APPLE_STORE_ISSUER_ID"],
      iat: Time.now.utc.to_i,
      exp: Time.now.utc.to_i + 300,
      aud: "appstoreconnect-v1",
      bid: ENV["APPLE_STORE_BUNDLE_ID"]
    }
    JWT.encode(payload, key, "ES256", headers)
  end
end
