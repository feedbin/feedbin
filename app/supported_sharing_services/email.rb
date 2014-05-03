class Email < Service

  def initialize(klass)
    @klass = klass
  end

  def share(params)
    reply_to = (@klass.email_address.present?) ? @klass.email_address : @klass.user.email
    from_name = (@klass.email_name.present?) ? @klass.email_name : @klass.user.email
    UserMailer.delay(queue: :critical).entry(params[:entry_id], params[:to], params[:subject], params[:body], reply_to, from_name, params[:readability])
    {message: "Email sent to #{params[:to]}."}
  end
end
