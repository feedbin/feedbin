class UserMailer < ActionMailer::Base

  def payment_receipt(billing_event)
    @billing_event = BillingEvent.find(billing_event)
    @user = @billing_event.billable
    mail to: @user.email, subject: '[Feedbin] Payment Receipt'
  end

  def payment_failed(billing_event)
    @billing_event = BillingEvent.find(billing_event)
    @user = @billing_event.billable
    mail to: @user.email, subject: '[Feedbin] Please Update Your Billing Information'
  end

  def password_reset(user_id)
    @user = User.find(user_id)
    mail to: @user.email, subject: '[Feedbin] Password Reset'
  end

  def trial_expiration(user_id)
    @user = User.find(user_id)
    mail to: @user.email, subject: '[Feedbin] Your Trial is About to End'
  end

end
