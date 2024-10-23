class AppStoreNotificationProcessor
  include Sidekiq::Worker
  sidekiq_options queue: :default_critical

  PRODUCTS = {
    "yearly_v1"         => "app-subscription",
    "yearly_pro_v1"     => "app-subscription",
    "monthly_pro_v1"    => "app-subscription",
    "yearly_podcast_v1" => "podcast-subscription",
    "yearly_podcast_v2" => "podcast-subscription",
    "yearly_podcast_v3" => "podcast-subscription",
    "yearly_podcast_v4" => "podcast-subscription",
  }

  def perform(token, user_id = nil)
    @token = token
    @user = User.find_by_id(user_id)
    notification = user.app_store_notifications.create_with(
      notification_type: data.safe_dig("notificationType"),
      subtype: data.safe_dig("subtype"),
      original_transaction_id: original_transaction_id,
      version: data.safe_dig("version"),
      data: data
    ).find_or_create_by!(notification_id: data.safe_dig("notificationUUID"))

    return unless notification.processed_at.nil?

    if notification.notification_type == "DID_FAIL_TO_RENEW" && notification.subtype == "GRACE_PERIOD"
      user.billing_issue!
    end

    if notification.notification_type == "DID_RENEW" || notification.notification_type == "SUBSCRIBED"
      user.activate
      user.free_ok = true
      user.plan = plan(notification)
      user.save
    end

    if notification.notification_type == "EXPIRED" || notification.notification_type == "REFUND"
      user.deactivate
    end

    notification.touch(:processed_at)
  end

  private

  def plan(notification)
    plan_name = PRODUCTS.fetch(product_id, "app-subscription")
    Plan.find_by_stripe_id(plan_name)
  end

  def user
    @user ||= begin
      match = AppStoreNotification.where(original_transaction_id: original_transaction_id).take
      return match&.user unless match&.user.nil?
      AuthenticationToken.app.active.where(uuid: app_account_token).sole.user
    end
  end

  def data
    @data ||= begin
      decode(@token).tap do |hash|
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

  def decode(data)
    _, payload, _ = data.split(".")
    JSON.load(Base64.decode64(payload))
  end
end
