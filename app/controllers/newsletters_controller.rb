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
    token = params[:token].split("+").first
    if AuthenticationToken.newsletters.active.where(token: token).exists?
      body = request.body.read
      begin
        NewsletterReceiver.perform_async(params[:token], body)
      rescue Encoding::UndefinedConversionError
        NewsletterReceiver.perform_async(params[:token], body.force_encoding(Encoding::UTF_8))
      end
    end
    head :ok
  end

  private

  def authorize
    http_basic_authenticate_or_request_with name: "newsletters", password: ENV["NEWSLETTER_PASSWORD"], realm: "Feedbin Newsletters"
  end
end
