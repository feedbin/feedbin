class DeletedUser < ApplicationRecord
  def self.search(query)
    where("email like ?", "%#{query}%")
  end

  scope :holding, ->(store, external_id) { where("store_subscriptions @> ?", [{store: store, external_id: external_id}].to_json) }

  # Says once, to the address the account had, that a store still charges for it.
  def store_still_billing(store)
    return if store_billing_notified_at
    update!(store_billing_notified_at: Time.current)
    UserMailer.store_still_billing(email, store.to_s).deliver_later
  end

  def stripe_url
    "https://manage.stripe.com/customers/#{customer_id}"
  end

  def deleted?
    true
  end
end
