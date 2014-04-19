class UserMailer < ActionMailer::Base

  default from: "Feedbin <#{ENV['FROM_ADDRESS']}>"

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

  def password_reset(user_id, reset_token)
    @user = User.find(user_id)
    @reset_token = reset_token
    mail to: @user.email, subject: '[Feedbin] Password Reset'
  end

  def trial_expiration(user_id)
    @user = User.find(user_id)
    mail to: @user.email, subject: '[Feedbin] Your Trial is About to End'
  end

  def starred_export_download(user_id, download_link)
    @user = User.find(user_id)
    @download_link = download_link
    mail to: @user.email, subject: '[Feedbin] Starred Items Export Complete'
  end

  def entry(entry_id, to, subject, body, reply_to, email_name)
    @entry = Entry.find(entry_id)
    @body = body

    if subject.blank?
      subject = @entry.title
    end

    headers['X-MC-InlineCSS'] = "true"
    headers['X-MC-Autotext'] = "true"
    headers['X-MC-SigningDomain'] = "feedbin.io"
    mail to: to, subject: subject, reply_to: reply_to, from: "#{email_name} <#{ENV['NOTIFICATION_EMAIL']}>"
  end

  def kindle(entry_id, kindle_address)
    @entry = Entry.find(entry_id)
    attachments["#{@entry.title}.html"] = render_to_string
    mail to: kindle_address, subject: @entry.title, body: '', from: ENV['KINDLE_EMAIL']
  end

end
