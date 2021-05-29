class NewslettersController < ApplicationController
  skip_before_action :verify_authenticity_token
  skip_before_action :authorize, only: [:create]

  def create
    newsletter = Newsletter.new(params)
    user = AuthenticationToken.newsletters.active.where(token: newsletter.token).take&.user
    if user && newsletter.valid?
      NewsletterEntry.create(newsletter, user)
    end
    active = user ? !user.suspended : false
    Librato.increment "newsletter.user_active.#{active}"
    head :ok
  end

  def raw
    token = EmailNewsletter.token(params[:token])
    if AuthenticationToken.newsletters.active.where(token: token).exists?
      NewsletterReceiver.perform_async(params[:token], decoded(request.body.read))
    end
    head :ok
  end

  private

  def decoded(body)
    begin
      JSON.generate(body)
    rescue Encoding::UndefinedConversionError
      begin
        body = body.force_encoding(Encoding::UTF_8)
        JSON.generate(body)
      rescue JSON::GeneratorError
        body = body.encode(Encoding::UTF_8, invalid: :replace, undef: :replace, replace: "?")
      end
    end
    body
  end

  def authorize
    http_basic_authenticate_or_request_with name: "newsletters", password: ENV["NEWSLETTER_PASSWORD"], realm: "Feedbin Newsletters"
  end
end
