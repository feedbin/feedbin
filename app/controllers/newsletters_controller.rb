class NewslettersController < ApplicationController
  skip_before_action :verify_authenticity_token

  def create
    NewsletterProcessor.perform_async(params[:newsletter][:to], params[:newsletter][:url])
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
  rescue JSON::GeneratorError
    body.encode(Encoding::UTF_8, invalid: :replace, undef: :replace, replace: "?")
  end

  def authorize
    http_basic_authenticate_or_request_with name: "newsletters", password: ENV["NEWSLETTER_PASSWORD"], realm: "Feedbin Newsletters"
  end
end
