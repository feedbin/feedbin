class BillingEvent < ApplicationRecord
  attr_accessor :details

  belongs_to :billable, polymorphic: true

  validates_uniqueness_of :event_id

  before_validation :build_event
  after_commit :process_event, on: :create

  def build_event
    self.event_type = info["type"]
    self.event_id = info["id"]

    customer = event_object.dig("customer")
    if event_object["object"] == "customer"
      customer = event_object["id"]
    end

    if customer
      self.billable = User.find_by_customer_id(customer)
    end
  end

  def process_event
    if charge_succeeded?
      UserMailer.delay(queue: :critical).payment_receipt(id)
    end

    if charge_failed?
      UserMailer.delay(queue: :critical).payment_failed(id)
    end

    if subscription_deactivated?
      billable.deactivate
    end

    if subscription_reactivated?
      billable.activate
    end
  end

  def charge_succeeded?
    "charge.succeeded" == event_type
  end

  def charge_failed?
    "invoice.payment_failed" == event_type
  end

  def subscription_deactivated?
    "customer.subscription.updated" == event_type &&
    event_object["status"] == "unpaid"
  end

  def subscription_reactivated?
    "customer.subscription.updated" == event_type &&
    event_object["status"] == "active" &&
    info.dig("data", "previous_attributes", "status") == "unpaid"
  end

  def invoice
    if event_type == "charge.succeeded"
      Rails.cache.fetch("#{event_object["invoice"]}") do
        JSON.parse(Stripe::Invoice.retrieve(event_object["invoice"]).to_json)
      end
    else
      nil
    end
  end

  def invoice_items
    if self.event_type == "charge.succeeded"
      Rails.cache.fetch("#{event_object["invoice"]}:lines") do
        JSON.parse(Stripe::Invoice.retrieve(event_object["invoice"]).lines.all(limit: 10).to_json)
      end
    else
      nil
    end
  end

  def details
    @details ||= Stripe::StripeObject.construct_from(self.info)
  end

  def event_object
    info["data"]["object"]
  end

  def receipt_date
    Time.at(event_object["created"]).to_s(:date)
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
end
