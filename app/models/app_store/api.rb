# The App Store Server API, for the two things only Apple can say or do: a
# subscription's state now, and which account token it carries.
module AppStore
  class Api
    class Error < StandardError
      attr_reader :status

      def initialize(status, body)
        @status = status
        super("App Store Server API #{status}: #{body.to_s[0, 200]}")
      end
    end

    HOSTS = {
      "production" => "https://api.storekit.itunes.apple.com",
      "sandbox" => "https://api.storekit-sandbox.itunes.apple.com"
    }.freeze

    def self.configured?
      %w[APPLE_STORE_KEY APPLE_STORE_KEY_ID APPLE_STORE_ISSUER_ID].all? { ENV[_1].present? }
    end

    def initialize(bundle_id:, environment: "production")
      @bundle_id = bundle_id
      @host = HOSTS.fetch(environment.to_s.downcase, HOSTS["production"])
    end

    # The subscription's state as Apple has it now, or nil when Apple doesn't
    # know the transaction in this environment.
    def subscription_state(original_transaction_id)
      response = client.get("#{@host}/inApps/v1/subscriptions/#{original_transaction_id}")
      return nil if response.status.to_i == 404
      raise Error.new(response.status.to_i, response.body) unless response.status.success?

      last = Array(response.parse["data"]).flat_map { Array(_1["lastTransactions"]) }
        .find { _1["originalTransactionId"] == original_transaction_id }
      return nil unless last

      SubscriptionState.new(
        transaction: SignedPayload.read(last["signedTransactionInfo"]),
        renewal: last["signedRenewalInfo"] && SignedPayload.read(last["signedRenewalInfo"]),
        status: last["status"]
      )
    end

    # Replaces the account token Apple stamps on the subscription's
    # transactions, so its notifications name the account that now holds it.
    def set_app_account_token(original_transaction_id, token)
      response = client.put("#{@host}/inApps/v1/transactions/#{original_transaction_id}/appAccountToken", json: {appAccountToken: token})
      raise Error.new(response.status.to_i, response.body) unless response.status.success?
      true
    end

    private

    def client
      HTTP.timeout(write: 5, connect: 5, read: 10).auth("Bearer #{token}")
    end

    def token
      key = OpenSSL::PKey.read(File.read(ENV["APPLE_STORE_KEY"]))
      now = Time.now.utc.to_i
      payload = {iss: ENV["APPLE_STORE_ISSUER_ID"], iat: now, exp: now + 300, aud: "appstoreconnect-v1", bid: @bundle_id}
      JWT.encode(payload, key, "ES256", {alg: "ES256", kid: ENV["APPLE_STORE_KEY_ID"], typ: "JWT"})
    end
  end
end
