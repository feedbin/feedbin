class EmailsController < ApplicationController
  skip_before_action :verify_authenticity_token
  skip_before_action :authorize

  respond_to :json

  def create
    if user = User.find_by(inbound_email_token: params[:MailboxHash])
      feed_url = params[:TextBody].try(:strip)
      finder = FeedFinder.new(feed_url)

      feeds = finder.create_feeds!
      if feeds
        feed = feeds.first
        user.subscriptions.find_or_create_by(feed: feed)
      end
    end
  ensure
    head :ok
  end
end
