# Words for the admin's pages about what an account pays and to whom.
module AdminBillingHelper
  BILLERS = {"web" => "Card, through Stripe", "apple" => "App Store", "google" => "Google Play"}.freeze
  TONES = {good: "bg-green-600", warn: "bg-orange-600", bad: "bg-red-600"}.freeze

  # An account's billing at a glance: where it stands, what it is on, the one
  # line of price and date, and what can be done about it.
  Summary = Struct.new(:tone, :status, :headline, :line, :note, keyword_init: true)

  def biller_name(source)
    BILLERS.fetch(source.to_s, "Nobody")
  end

  def billing_summary(user, subscription = user.billing_subscription)
    source = user.billing_source(subscription)
    case source
    when "apple", "google" then store_summary(user, subscription)
    when "web" then web_summary(user)
    else unbilled_summary(user)
    end
  end

  def closed_summary(deleted_user)
    billed = deleted_user.store_subscriptions.map { biller_name(_1["store"]) }.uniq
    Summary.new(
      tone: billed.any? ? :warn : :bad,
      status: "Closed",
      headline: "Closed account",
      line: [("Closed #{deleted_user.created_at.to_formatted_s(:date)}" if deleted_user.created_at), (billed.any? ? "Had a subscription with #{billed.to_sentence}" : nil)].compact.join(" · "),
      note: if billed.empty?
        "No store billed this account."
      elsif deleted_user.store_billing_notified_at
        "Only its owner can cancel a store's subscription. Told it was still being charged on #{deleted_user.store_billing_notified_at.to_formatted_s(:date)}."
      else
        "Only its owner can cancel a store's subscription. It is emailed once if the store charges again."
      end
    )
  end

  def summary_dot(summary)
    tag.span(class: "block rounded-full h-[8px] w-[8px] #{TONES.fetch(summary.tone)}")
  end

  # A store subscription in a line: where it stands and its next date.
  def store_subscription_standing(subscription)
    date = subscription.expires_at&.to_formatted_s(:date)
    case subscription.status
    when "active" then subscription.auto_renew ? "Renews #{date}" : "Ends #{date}"
    when "grace" then "In grace until #{subscription.grace_expires_at&.to_formatted_s(:date)}"
    when "retrying" then "Payment failed, the store is retrying"
    when "revoked" then "Refunded"
    else "Ended #{date}"
    end
  end

  def store_subscription_price(subscription)
    return nil unless subscription.price && subscription.currency
    every = {"monthly" => " a month", "yearly" => " a year"}[subscription.period]
    "#{number_with_precision(subscription.price, precision: 2)} #{subscription.currency}#{every}"
  end

  # A payment's amount in the currency it was charged in, which isn't always dollars.
  def payment_amount(purchase)
    [purchase.receipt_amount && number_with_precision(purchase.receipt_amount, precision: 2), purchase.currency, purchase.receipt_description].compact_blank.join(" ")
  end

  def payment_source(purchase)
    case purchase
    when BillingEvent then "Card, through Stripe"
    when AppStoreNotification then "App Store subscription"
    when InAppPurchase then "App Store one-time purchase"
    end
  end

  def notification_name(notification)
    [notification.notification_type, notification.subtype].compact.join(" / ").humanize.titleize
  end

  private

  def plan_headline(period)
    period ? "Feedbin #{period.capitalize}" : "Feedbin"
  end

  def store_summary(user, subscription)
    store = biller_name(subscription.store)
    tone, status, note =
      if subscription.grace?
        [:warn, "Payment failed", "#{store} is retrying the card. The account keeps its service until the grace period ends."]
      elsif subscription.active? && !user.suspended
        subscription.auto_renew ? [:good, "Active", "Only the customer can cancel or change it, in their #{store} subscriptions."] :
          [:warn, "Active, not renewing", "The customer turned renewal off. Service ends with the paid time."]
      elsif subscription.revoked?
        [:bad, "Lapsed", "#{store} refunded the purchase. The customer can subscribe again in the app."]
      elsif subscription.retrying?
        [:bad, "Lapsed", "A payment failed and #{store} is still retrying. No service until it goes through."]
      elsif user.suspended
        [:bad, "Lapsed", "The subscription ended. The customer can subscribe again in the app."]
      else
        [:warn, "Active, subscription ended", "The account has service though its #{store} subscription has ended."]
      end
    Summary.new(
      tone: tone, status: status, headline: plan_headline(subscription.period),
      line: [store_subscription_price(subscription), store_subscription_standing(subscription), store].compact.join(" · "),
      note: note
    )
  end

  def web_summary(user)
    period = user.plan.name.downcase.presence_in(%w[monthly yearly])
    price = user.plan.price.to_f.positive? ? "#{number_to_currency(user.plan.price)} a #{user.plan.period}" : nil
    if user.suspended
      Summary.new(tone: :bad, status: "Lapsed", headline: plan_headline(period), line: [price, biller_name("web")].compact.join(" · "),
        note: "The card plan is not being paid. Stripe has the invoices and the card.")
    else
      Summary.new(tone: user.billing_issue? ? :warn : :good, status: user.billing_issue? ? "Payment failed" : "Active", headline: plan_headline(period),
        line: [price, biller_name("web")].compact.join(" · "), note: "The plan, the card, invoices and refunds are in Stripe.")
    end
  end

  def unbilled_summary(user)
    date = user.expires_at&.to_formatted_s(:date)
    if user.trial_plan?
      ended = user.suspended || user.expires_at&.past?
      Summary.new(tone: ended ? :bad : :good, status: ended ? "Lapsed" : "On trial", headline: "Trial",
        line: [(ended ? "Ended #{date}" : "Ends #{date}" if date), "Nobody bills this account"].compact.join(" · "),
        note: "The customer can subscribe in the app or on the website.")
    elsif user.timed_plan?
      ended = user.suspended || user.expires_at&.past?
      Summary.new(tone: ended ? :bad : :good, status: ended ? "Lapsed" : "Active", headline: "Paid ahead",
        line: [(ended ? "Ended #{date}" : "Until #{date}" if date), "No renewal"].compact.join(" · "),
        note: "Bought as a one-time purchase in an older app.")
    elsif user.suspended
      Summary.new(tone: :bad, status: "Lapsed", headline: user.plan.name, line: "Nobody bills this account", note: "The customer can subscribe in the app or on the website.")
    else
      Summary.new(tone: :good, status: "Active", headline: user.plan.name, line: "Nothing is charged", note: "No store and no card bills this account.")
    end
  end
end
