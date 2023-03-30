class FeedsController < ApplicationController
  before_action :correct_user, only: :update

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

  def search
    @user = current_user
    @feeds = FeedFinder.feeds(params[:q], twitter_auth: @user.twitter_auth, username: params[:username], password: params[:password])
    @feeds.map { |feed| feed.priority_refresh(@user) }
    @tag_editor = TagEditor.new(@user, nil)
  rescue Feedkit::Unauthorized => exception
    @feeds = nil
    if exception.basic_auth?
      @basic_auth = true
      @feed_url = params[:q]
    end
  rescue => exception
    ErrorService.notify(exception)
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
