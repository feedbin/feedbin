class UpdateStatementDescriptor
  include Sidekiq::Worker
  sidekiq_options queue: :default_critical

  def perform(billing_event_id)
    billing_event = BillingEvent.find(billing_event_id)
    return unless billing_event.event_type == "invoice.created"
    descriptor = [ENV.fetch("STRIPE_DESCRIPTOR"), billing_event.billable_id].join(" ")
    Stripe::Invoice.update(billing_event.details.data.object.id, {statement_descriptor: descriptor})
  end
end


