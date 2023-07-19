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
    @feeds = FeedFinder.feeds(params[:q], username: params[:username], password: params[:password])
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

  def assign_new_feeds(tag_id, user_id)
    feeds_ids = get_all_feeds_on_specifi_tag(tag_id)
    # Insert operations
    feeds_ids.each do |feed_id|
      Subscription.new(user_id: user_id, feed_id: feed_id).save # Subcribe to all new feeds
      Tagging.new(feed_id: feed_id, user_id: user_id, tag_id: tag_id).save # Insert new feed to the folder
    end
  end

  private

  def correct_user
    unless current_user.subscribed_to?(params[:id])
      render_404
    end
  end

  def get_all_feeds_on_specifi_tag(tag_id)
    # Selects all feeds on specific tag
    feeds_ids = Tag.find(tag_id).feeds.pluck(:id)
  end
end
