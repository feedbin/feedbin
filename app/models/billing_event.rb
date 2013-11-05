class BillingEvent < ActiveRecord::Base
  serialize :details
  belongs_to :billable, polymorphic: true

  validates_uniqueness_of :event_id

  before_validation :build_event
  after_commit :process_event, on: :create

  def build_event
    self.event_type = details.type
    self.event_id = details.id

    if details.data.object.respond_to?(:customer)
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
    case event_type
    when 'charge.succeeded'
      billable.update_attributes(suspended: false)
      UserMailer.delay(queue: :critical).payment_receipt(id)
    when 'invoice.payment_failed'
      billable.update_attributes(suspended: true)
      UserMailer.delay(queue: :critical).payment_failed(id)
    end
  end


end
