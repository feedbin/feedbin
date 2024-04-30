class NewslettersController < ApplicationController
  skip_before_action :verify_authenticity_token

  def create
    NewsletterReceiver.perform_async(params[:newsletter][:to], params[:newsletter][:url])
    head :ok
  end

  private

  def authorize
    http_basic_authenticate_or_request_with name: "newsletters", password: ENV["NEWSLETTER_PASSWORD"], realm: "Feedbin Newsletters"
  end
end
