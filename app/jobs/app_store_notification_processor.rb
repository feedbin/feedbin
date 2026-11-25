# One App Store Server Notification: recorded, and the subscription it speaks
# of brought up to date. The subscription is found by its transaction. The
# account token a purchase carries only says who is buying.
class AppStoreNotificationProcessor
  include Sidekiq::Worker
  sidekiq_options queue: :default_critical

  # Kept for the receipts the web shows (AppStoreNotification#receipt_description).
  PRODUCTS = StoreSubscription::PRODUCTS.transform_values { _1[:plan] }

  PURCHASES = %w[SUBSCRIBED].freeze
  CHARGES = %w[SUBSCRIBED DID_RENEW].freeze
  ENDINGS = %w[EXPIRED GRACE_PERIOD_EXPIRED].freeze

  # user_id: an account named by hand, from the console, for a purchase
  # nothing else could place.
  def perform(token, user_id = nil)
    @payload = AppStore::SignedPayload.read(token)
    @named_user = User.find_by_id(user_id)
    return unless state.external_id

    notification = AppStoreNotification.create_with(
      notification_type: type,
      subtype: @payload["subtype"],
      original_transaction_id: state.external_id,
      version: @payload["version"],
      data: data
    ).find_or_create_by!(notification_id: @payload["notificationUUID"])
    return unless notification.processed_at.nil?

    subscription = record
    notification.update!(user: subscription&.user, processed_at: Time.current)
    unplaced if subscription.nil?
  end

  private

  def record
    StoreSubscription.record(state, user: buyer)
  rescue StoreSubscription::OwnedByAnotherAccount
    StoreSubscription.record(state)
  end

  # Who a new subscription goes to: the account whose token the purchase
  # carries. A subscription already held is only handed over by a purchase.
  def buyer
    return @named_user if @named_user
    return nil unless PURCHASES.include?(type) || !StoreSubscription.exists?(store: :apple, external_id: state.external_id)
    return nil unless state.app_account_token
    AuthenticationToken.app.active.find_by(uuid: state.app_account_token)&.user
  rescue ActiveRecord::StatementInvalid
    nil # not a UUID
  end

  # No account holds it and none was named. A deleted account is told it is
  # still being charged; anything else is someone paying for nothing we know of.
  def unplaced
    deleted_user = DeletedUser.holding(:apple, state.external_id).first
    if deleted_user
      deleted_user.store_still_billing(:apple) if CHARGES.include?(type) && recent?
    else
      ErrorService.notify(
        error_class: "AppStoreNotificationProcessor",
        error_message: "A notification for a subscription no account holds",
        parameters: {notification_type: type, original_transaction_id: state.external_id, product_id: transaction["productId"]}
      )
    end
  end

  def state
    @state ||= AppStore::SubscriptionState.new(
      transaction: transaction,
      renewal: renewal,
      status: @payload.dig("data", "status"),
      ended: ENDINGS.include?(type),
      environment: @payload.dig("data", "environment")
    )
  end

  def type
    @payload["notificationType"]
  end

  # News of a charge is only worth an email while it is news: a notification
  # processed again long after says nothing the person can act on.
  def recent?
    signed = @payload["signedDate"]
    signed.nil? || Time.at(signed / 1000.0) > 3.days.ago
  end

  def transaction
    @transaction ||= read(@payload.dig("data", "signedTransactionInfo"))
  end

  def renewal
    @renewal ||= read(@payload.dig("data", "signedRenewalInfo"))
  end

  # The notification as it is kept: the two signed parts read out in place.
  def data
    @payload.deep_dup.tap do |hash|
      next unless hash["data"]
      hash["data"]["signedTransactionInfo"] = transaction
      hash["data"]["signedRenewalInfo"] = renewal
    end
  end

  def read(token)
    token.present? ? AppStore::SignedPayload.read(token) : {}
  end
end
