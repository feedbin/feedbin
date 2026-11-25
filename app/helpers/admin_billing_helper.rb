# Words for the admin's pages about what an account pays and to whom.
module AdminBillingHelper
  BILLERS = {"web" => "Feedbin, by card (Stripe)", "apple" => "App Store", "google" => "Google Play"}.freeze

  def biller_name(source)
    BILLERS.fetch(source.to_s, "Nobody")
  end

  # Where the account stands, in a few words.
  def account_standing(user)
    if user.suspended
      "Suspended"
    elsif user.trial_plan?
      user.expires_at&.past? ? "Trial ended" : "On trial"
    elsif user.timed_plan?
      user.expires_at&.past? ? "Paid time ended" : "Paid ahead"
    else
      "Active"
    end
  end

  # A store subscription in a line: where it stands and its next date.
  def store_subscription_standing(subscription)
    date = subscription.expires_at&.to_formatted_s(:date)
    case subscription.status
    when "active" then subscription.auto_renew ? "Active, renews #{date}" : "Active, renewal off, ends #{date}"
    when "grace" then "Payment failed, in grace until #{subscription.grace_expires_at&.to_formatted_s(:date)}"
    when "retrying" then "Payment failed, no service, Apple still retrying"
    when "revoked" then "Refunded"
    else "Ended #{date}"
    end
  end

  def store_subscription_price(subscription)
    return nil unless subscription.price && subscription.currency
    "#{number_with_precision(subscription.price, precision: 2)} #{subscription.currency}"
  end

  # A payment's amount in the currency it was charged in, which isn't always dollars.
  def payment_amount(purchase)
    [purchase.receipt_amount && number_with_precision(purchase.receipt_amount, precision: 2), purchase.currency, purchase.receipt_description].compact.join(" ")
  end

  def payment_source(purchase)
    case purchase
    when BillingEvent then "Card (Stripe)"
    when AppStoreNotification then "App Store subscription"
    when InAppPurchase then "App Store one-time purchase"
    end
  end

  def notification_name(notification)
    [notification.notification_type, notification.subtype].compact.join(" / ").humanize.titleize
  end
end
