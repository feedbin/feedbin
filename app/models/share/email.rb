class Share::Email < Share::Service
  def initialize(klass)
    @klass = klass
  end

  def share(params)
    reply_to = @klass.email_address.present? ? @klass.email_address : @klass.user.email
    from_name = @klass.email_name.present? ? @klass.email_name : @klass.user.email
    update_completions(params[:to])
    EntryMailer.delay(queue: :critical).mailer(params[:entry_id], params[:to], params[:subject], params[:body], reply_to, from_name, params[:readability])
    {message: "Email sent to #{params[:to]}."}
  end

  def update_completions(to)
    new_contacts = to.to_s.split(",").map { |contact| contact.strip }
    @klass.update_completions(new_contacts)
  end
end
