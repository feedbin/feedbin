class EntryMailer < ActionMailer::Base

  default from: "Feedbin <#{ENV['NOTIFICATION_EMAIL']}>"

  self.smtp_settings = self.smtp_settings.merge({
    user_name: ENV['SMTP_BULK_USERNAME'] || ENV['SMTP_USERNAME'],
    password: ENV['SMTP_BULK_PASSWORD'] || ENV['SMTP_PASSWORD']
  })

  def mailer(entry_id, to, subject, body, reply_to, email_name, readability)
    entry = Entry.find(entry_id)
    message = body

    if subject.blank?
      subject = entry.title
    end

    article = Share::Service.determine_content({entry_id: entry_id, readability: readability})
    article = render_entry(entry, article, message)
    premailer = Premailer.new(article, with_html_string: true)

    mail(to: to, subject: subject, reply_to: reply_to, from: "#{email_name} <#{ENV['NOTIFICATION_EMAIL']}>") do |format|
      format.html {render inline: premailer.to_inline_css}
      format.text {render text: premailer.to_plain_text}
    end
  end

  private

  def render_entry(entry, content, message)
    action_view = ActionView::Base.new()
    action_view.view_paths = ActionController::Base.view_paths
    action_view.extend(ApplicationHelper)
    action_view.render(template: "entry_mailer/mailer.html.erb", locals: {entry: entry, content: content, message: message})
  end


end
