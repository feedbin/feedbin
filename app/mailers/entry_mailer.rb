class EntryMailer < ApplicationMailer
  default from: "Feedbin <#{ENV["NOTIFICATION_EMAIL"]}>"

  self.postmark_settings = { api_key: ENV["POSTMARK_API_KEY_BULK"] || ENV["POSTMARK_API_KEY"] }

  def mailer(entry_id, to, subject, body, reply_to, email_name, readability)
    @entry = Entry.find(entry_id)
    @message = body
    @content = Share::Service.determine_content({entry_id: entry_id, readability: readability})
    if subject.blank?
      subject = @entry.title
    end
    mail(to: to, subject: subject, reply_to: reply_to, from: from_address(email_name))
  end

  private

  # email_name is the user's own "Full Name" setting. A comma is the address
  # separator in this header, so interpolating the name produced a list —
  # "Ubois, Ben <addr>" parses as the address "Ubois" plus the real one.
  # Mail::Address quotes the display name when it needs quoting.
  def from_address(email_name)
    address = Mail::Address.new(ENV["NOTIFICATION_EMAIL"])
    address.display_name = email_name if email_name.present?
    address.format
  end
end
