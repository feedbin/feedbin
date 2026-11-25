# What Apple says about one subscription, from a signed transaction and its
# renewal info, as the attributes of a StoreSubscription.
module AppStore
  class SubscriptionState
    # Apple's status numbers, from the App Store Server API and notifications.
    STATUSES = {1 => :active, 2 => :expired, 3 => :retrying, 4 => :grace, 5 => :revoked}.freeze

    attr_reader :transaction, :renewal

    # status: Apple's own number when it gave one. ended: the notification said
    # the subscription is over, whatever the dates say.
    def initialize(transaction:, renewal: nil, status: nil, ended: false, environment: nil)
      @transaction = transaction || {}
      @renewal = renewal || {}
      @apple_status = status
      @ended = ended
      @environment = environment
    end

    def store = :apple

    def external_id = transaction["originalTransactionId"]

    def bundle_id = transaction["bundleId"]

    def app_account_token = transaction["appAccountToken"]

    def signed_at
      time([transaction["signedDate"], renewal["signedDate"]].compact.max)
    end

    def status
      return STATUSES.fetch(@apple_status) if STATUSES.key?(@apple_status)
      return :revoked if transaction["revocationDate"]
      return :grace if grace_expires_at&.future? && !@ended
      return :retrying if renewal["isInBillingRetryPeriod"]
      return :expired if @ended
      expires_at&.future? ? :active : :expired
    end

    def entitling?
      [:active, :grace].include?(status)
    end

    def expires_at = time(transaction["expiresDate"])

    def grace_expires_at = time(renewal["gracePeriodExpiresDate"])

    def attributes
      {
        app_identifier: bundle_id,
        environment: (@environment || transaction["environment"] || renewal["environment"] || "Production").downcase,
        product_id: transaction["productId"],
        status: status,
        expires_at: expires_at,
        grace_expires_at: grace_expires_at,
        auto_renew: renewal.fetch("autoRenewStatus", 1) == 1,
        renews_as: (renewal["autoRenewProductId"] unless renewal["autoRenewProductId"] == transaction["productId"]),
        price_milliunits: transaction["price"],
        currency: transaction["currency"],
        signed_at: signed_at,
        verified_at: Time.current
      }
    end

    private

    def time(milliseconds)
      milliseconds && Time.at(milliseconds / 1000.0)
    end
  end
end
