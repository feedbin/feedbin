class AppStoreNotificationProcessor
  include Sidekiq::Worker
  sidekiq_options queue: :critical

  def perform(token)
    @token = token
    notification = user.app_store_notifications.create_with(
      notification_type: data.dig("notificationType"),
      subtype: data.dig("subtype"),
      original_transaction_id: original_transaction_id,
      version: data.dig("version"),
      data: data
    ).find_or_create_by!(notification_id: data.dig("notificationUUID"))

    return unless notification.processed_at.nil?

    if notification.notification_type == "DID_FAIL_TO_RENEW" && notification.subtype == "GRACE_PERIOD"
      user.billing_issue!
    end

    if notification.notification_type == "DID_RENEW" || notification.notification_type == "SUBSCRIBED"
      user.activate
    end

    if notification.notification_type == "EXPIRED" || notification.notification_type == "REFUND"
      user.deactivate
    end

    notification.touch(:processed_at)
  end

  private

  def user
    @user ||= begin
      match = AppStoreNotification.where(original_transaction_id: original_transaction_id).take
      return match.user unless match.nil?
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
    data.dig("data", "signedTransactionInfo", "originalTransactionId")
  end

  def app_account_token
    data.dig("data", "signedTransactionInfo", "appAccountToken")
  end

  def decode(data)
    _, payload, _ = data.split(".")
    JSON.load(Base64.decode64(payload))
  end
end
