class BillingEvent < ActiveRecord::Base
  serialize :details
  belongs_to :billable, polymorphic: true

  validates_uniqueness_of :event_id

  before_validation :build_event
  after_commit :process_event, on: :create

  def build_event
    self.event_type = details.type
    self.event_id = details.id

    if details.data.object['customer'].present?
      customer = details.data.object.customer
    elsif details.type == 'customer.created'
      customer = details.data.object.id
    else
      customer = nil
    end

    if customer
      self.billable = User.where(customer_id: customer).first
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
    'invoice.payment_failed' == event_type
  end

  def subscription_deactivated?
    "customer.subscription.updated" == event_type &&
    details.data.object.status == "unpaid"
  end

  def subscription_reactivated?
    "customer.subscription.updated" == event_type &&
    details.data.object.status == "active" &&
    details.data.try(:[], :previous_attributes).try(:[], :status) == "unpaid"
  end

end
