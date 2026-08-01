class BillingEvent < ApplicationRecord
  attr_accessor :details

  belongs_to :billable, polymorphic: true

  validates_uniqueness_of :event_id

  before_validation :build_event
  after_commit :process_event, on: :create

  def build_event
    self.event_type = info["type"]
    self.event_id = info["id"]

    customer = event_object.safe_dig("customer")
    if event_object["object"] == "customer"
      customer = event_object["id"]
    end

    if customer
      self.billable = User.find_by_customer_id(customer)
    end
  end

  def process_event
    if charge_succeeded?
      UserMailer.payment_receipt(id).deliver_later
    end

    if charge_failed?
      UserMailer.payment_failed(id).deliver_later
    end

    if subscription_reminder?
      UserMailer.subscription_reminder(id).deliver_later
    end

    if subscription_deactivated?
      billable.deactivate unless billable.plan.stripe_id == "free"
    end

    if subscription_reactivated?
      billable.activate
    end

    if invoice_created?
      UpdateStatementDescriptor.perform_async(id)
    end

    if payment_action_required?
      UserMailer.payment_action_required(id).deliver_later
    end
  end

  def charge_succeeded?
    event_type == "charge.succeeded"
  end

  def charge_failed?
    event_type == "invoice.payment_failed" && !awaiting_authentication?
  end

  # Stripe sends invoice.payment_failed alongside invoice.payment_action_required
  # when the charge was declined with `authentication_required`. The card is fine
  # in that case, so telling the customer to update their billing information
  # would be wrong — payment_action_required? sends them the right email.
  #
  # `payment_intent` is absent from invoice payloads rendered before 2019-02-11,
  # which just means the dunning email goes out as it always did.
  def awaiting_authentication?
    payment_intent_id = event_object["payment_intent"]
    return false if payment_intent_id.blank?

    intent = Stripe::PaymentIntent.retrieve(payment_intent_id, {stripe_version: STRIPE_INTENTS_API_VERSION})
    intent.status == "requires_action"
  rescue Stripe::StripeError
    false
  end

  def subscription_deactivated?
    event_type == "customer.subscription.updated" &&
      event_object["status"] == "unpaid"
  end

  def subscription_reactivated?
    event_type == "customer.subscription.updated" &&
      event_object["status"] == "active" &&
      info.safe_dig("data", "previous_attributes", "status") == "unpaid"
  end

  def subscription_reminder?
    event_type == "invoice.upcoming" &&
      event_object["amount_remaining"].present? &&
      event_object["amount_remaining"] >= 2_000 &&
      !billable.suspended?
  end

  def invoice_created?
    event_type == "invoice.created"
  end

  # The recurring charge was attempted and the bank wants the customer to
  # authenticate it. Nothing has failed yet — the invoice stays open until they
  # do, or until Stripe gives up retrying and sends invoice.payment_failed.
  #
  # Events can arrive for customers with no user here — a deleted account, or a
  # throwaway customer from `stripe trigger` — and there's nobody to email.
  def payment_action_required?
    event_type == "invoice.payment_action_required" && billable.present?
  end

  def invoice
    if event_type == "charge.succeeded" && event_object["invoice"]
      Rails.cache.fetch(event_object["invoice"].to_s) do
        JSON.parse(Stripe::Invoice.retrieve(event_object["invoice"]).to_json)
      end
    end
  end

  def invoice_items
    if event_type == "charge.succeeded" && event_object["invoice"]
      Rails.cache.fetch("#{event_object["invoice"]}:lines") do
        JSON.parse(Stripe::Invoice.retrieve(event_object["invoice"]).lines.list(limit: 10).to_json)
      end
    end
  end

  def details
    @details ||= Stripe::StripeObject.construct_from(info)
  end

  def event_object
    info["data"]["object"]
  end

  def receipt_date
    Time.at(event_object["created"]).to_formatted_s(:date)
  end

  def receipt_description
    ""
  end

  def receipt_amount
    event_object["amount"].to_f / 100
  end

  def currency
    event_object["currency"].upcase
  end

  def purchase_date
    Time.at(event_object["created"])
  end

  def period_end
    Time.at(event_object["period_end"])
  end
end
