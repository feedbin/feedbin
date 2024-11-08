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
  end

  def charge_succeeded?
    event_type == "charge.succeeded"
  end

  def charge_failed?
    event_type == "invoice.payment_failed"
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
