# What Apple says about a subscription, built by hand, and unsigned tokens in
# the shape of its notifications: enough for everything past signature checks.
module StoreSubscriptionHelper
  BUNDLE_ID = "com.feedbin.feedbin.app"

  def start_stripe
    StripeMock.start
    Plan.all.each do |plan|
      create_stripe_plan(plan)
    rescue Stripe::InvalidRequestError
      # two fixtures share an id
    end
    User.find_each do |user|
      user.update_column(:customer_id, Stripe::Customer.create(email: user.email, plan: user.plan.stripe_id).id)
    end
  end

  def apple_transaction(id: "1000", product: "monthly_pro_v1", expires: 1.month.from_now, signed: Time.now, token: nil, **extra)
    {
      "originalTransactionId" => id,
      "bundleId" => BUNDLE_ID,
      "productId" => product,
      "expiresDate" => milliseconds(expires),
      "signedDate" => milliseconds(signed),
      "price" => 5990,
      "currency" => "USD",
      "appAccountToken" => token
    }.compact.merge(extra.transform_keys(&:to_s))
  end

  def apple_renewal(product: "monthly_pro_v1", signed: Time.now, **extra)
    {"autoRenewStatus" => 1, "autoRenewProductId" => product, "signedDate" => milliseconds(signed)}.merge(extra.transform_keys(&:to_s))
  end

  def apple_state(renewal: {}, status: nil, ended: false, **transaction)
    AppStore::SubscriptionState.new(
      transaction: apple_transaction(**transaction),
      renewal: apple_renewal(product: transaction.fetch(:product, "monthly_pro_v1"), signed: transaction.fetch(:signed, Time.now), **renewal),
      status: status,
      ended: ended
    )
  end

  def apple_notification(type, subtype: nil, renewal: {}, without_renewal: false, **transaction)
    data = {"bundleId" => BUNDLE_ID, "environment" => "Production", "signedTransactionInfo" => unsigned(apple_transaction(**transaction))}
    data["signedRenewalInfo"] = unsigned(apple_renewal(product: transaction.fetch(:product, "monthly_pro_v1"), signed: transaction.fetch(:signed, Time.now), **renewal)) unless without_renewal
    unsigned({"notificationType" => type, "subtype" => subtype, "notificationUUID" => SecureRandom.uuid, "version" => "2.0", "signedDate" => milliseconds(Time.now), "data" => data}.compact)
  end

  # The mailer methods queued for later delivery.
  def queued_mail
    Sidekiq::Worker.jobs.select { _1["wrapped"].to_s == "ActionMailer::MailDeliveryJob" }.map { _1["args"].first["arguments"][1] }
  end

  def unsigned(claims)
    ["header", Base64.urlsafe_encode64(claims.to_json, padding: false), "signature"].join(".")
  end

  def milliseconds(time)
    (time.to_f * 1000).to_i
  end
end
