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
    update_auth_cookie(current_user)
    get_feeds_list
  end

  def search
    @user = current_user
    @query = params[:q].strip
    @feeds = if looks_like_url?(@query)
      FeedFinder.feeds(params[:q], username: params[:username], password: params[:password])
    else
      @search = true
      Feed.search(@query)
    end
    @feeds.map { |feed| feed.priority_refresh(@user) }

    @subscriptions = @user.existing_subscriptions(@feeds)

    taggings = TagEditor.taggings(@user)
    @tag_editor = TagEditor.new(taggings: taggings, user: @user, feed: nil)
  rescue Feedkit::Unauthorized => exception
    @feeds = nil
    if exception.basic_auth?
      @basic_auth = true
      @auth_attempted = params[:username].present? || params[:password].present?
    end
  rescue => exception
    ErrorService.notify(exception)
    @feeds = nil
  end

  private

  def correct_user
    unless current_user.subscribed_to?(params[:id])
      render_404
    end
  end
end
