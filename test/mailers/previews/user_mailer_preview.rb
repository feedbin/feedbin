# Preview all emails at http://localhost:3000/rails/mailers/marketing_mailer
class UserMailerPreview < ActionMailer::Preview
  def subscription_reminder
    UserMailer.subscription_reminder(BillingEvent.first.id)
  end

  # Only reads `billable`, so any billing event renders it.
  def payment_action_required
    event = BillingEvent.where(event_type: "invoice.payment_action_required").last || BillingEvent.first
    UserMailer.payment_action_required(event.id)
  end
end
