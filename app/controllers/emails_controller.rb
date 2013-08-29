class EmailsController < ApplicationController

  skip_before_action :verify_authenticity_token
  skip_before_action :authorize

  respond_to :json

  def create
    user = User.where(inbound_email_token: params[:MailboxHash]).first
    if user.present?
      url = params[:TextBody].try(:strip)
      result = FeedFetcher.new(url).create_feed!
      if result.feed
        user.safe_subscribe(result.feed)
      elsif result.feed_options.any?
        result = FeedFetcher.new(result.feed_options.first[:href]).create_feed!
        if result.feed
          user.safe_subscribe(result.feed)
        end
      end
    end
  rescue Exception
  ensure
    render nothing: true
  end

end


