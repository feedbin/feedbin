class FeedsController < ApplicationController
  before_action :correct_user, only: :update
  skip_before_action :authorize, only: [:push]
  skip_before_action :verify_authenticity_token, only: [:push]

  def update
    @user = current_user
    @feed = Feed.find(params[:id])
    @taggings = @feed.tag_with_params(params, @user)
    head :ok
  end

  def rename
    @user = current_user
    @subscription = @user.subscriptions.where(feed_id: params[:feed_id]).first!
    title = params[:feed][:title]
    @subscription.title = title.empty? ? nil : title
    @subscription.save
    @feed_order = @user.feed_order
  end

  def auto_update
    get_feeds_list
  end

  def push
    feed = Feed.find(params[:id])
    secret = Push.hub_secret(feed.id)

    response = ""
    status = :not_found
    if request.get?
      if params["hub.mode"] == "unsubscribe"
        Librato.increment "push.unsubscribe"
        feed.update(push_expiration: nil)
        response = params["hub.challenge"]
        status = :ok
      end
    else
      status = :ok
      PushUnsubscribe.perform_async(feed.id, params["hub.topic"])
      WebSubSubscribe.perform_async(feed.id)
    end

    render plain: response, status: status
  end

  def search
    @user = current_user
    if twitter_feed?(params[:q]) && !@user.twitter_enabled?
      session[:subscribe_query] = params[:q]
      render js: "window.location = '#{new_twitter_authentication_path}';"
    else
      @feeds = FeedFinder.feeds(params[:q], twitter_auth: @user.twitter_auth)
      @feeds.map { |feed| feed.priority_refresh(@user) }
      @tag_editor = TagEditor.new(@user, nil)
    end
  rescue => exception
    logger.info { "------------------------" }
    logger.info { exception.message }
    logger.info { exception.backtrace }
    logger.info { "------------------------" }
    Honeybadger.notify(exception)
    @feeds = nil
  end

  private

  def twitter_feed?(url)
    url = url.strip
    url.start_with?("@", "#", "http://twitter.com", "https://twitter.com", "http://mobile.twitter.com", "https://mobile.twitter.com", "twitter.com", "mobile.twitter.com")
  end

  def correct_user
    unless current_user.subscribed_to?(params[:id])
      render_404
    end
  end
end
