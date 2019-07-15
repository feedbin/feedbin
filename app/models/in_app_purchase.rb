class InAppPurchase < ApplicationRecord
  belongs_to :user

  validates :transaction_id, uniqueness: true

  after_commit :extend_subscription, on: :create

  def self.create_from_receipt_json(user, receipt_json, response)
    create({
      transaction_id: receipt_json["transaction_id"],
      purchase_date: Time.at(receipt_json["purchase_date_ms"].to_i / 1_000),
      receipt: receipt_json,
      response: response,
      user: user,
    })
  end

  def extend_subscription
    expires_at = user.expires_at
    base_date = Time.now
    if expires_at.present? && expires_at.future?
      base_date = expires_at
    end
    new_expires_at = base_date + product[:time]
    user.plan = Plan.find_by_stripe_id("timed")
    user.expires_at = new_expires_at
    user.suspended = false
    user.save
    user.subscriptions.update_all(active: true)
  end

  def product_id
    @product_id ||= receipt["product_id"]
  end

  def product
    @product ||= Feedbin::Application.config.iap[product_id]
  end

  def receipt_amount
    product[:amount].to_f / 100
  end

  def receipt_date
    purchase_date.to_s(:date)
  end

  def receipt_description
    product[:name]
  end

  def currency
    "USD"
  end
end
