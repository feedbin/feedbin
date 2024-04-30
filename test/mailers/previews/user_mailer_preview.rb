# Preview all emails at http://localhost:3000/rails/mailers/marketing_mailer
class UserMailerPreview < ActionMailer::Preview
  def subscription_reminder
    UserMailer.subscription_reminder(BillingEvent.first.id)
  end
end
