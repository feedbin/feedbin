class FixFeedsController < ApplicationController
  before_action :set_subscription, only: [:update, :destroy]

  def index
    @user = current_user
    @subscriptions = @user
      .subscriptions
      .fix_suggestion_present
      .includes(feed: [:discovered_feeds])
      .sort_by { _1.title || _1.feed.title }

    view = FixFeeds::IndexView.new(
      user: @user,
      subscriptions: @subscriptions,
    )

    render view, layout: "settings"
  end

  def update
    @subscription.fix_suggestion_none!
    @subscriptions = current_user.subscriptions.fix_suggestion_present

    args = [current_user.id, @subscription.id, params[:discovered_feed][:id].to_i]

    respond_to do |format|
      format.html do
        replaced = FeedReplacer.new.perform(*args)
        redirect_to edit_settings_subscription_url(replaced), notice: "Subscription successfully replaced."
      end
      format.js do
        FeedReplacer.perform_async(*args)
      end
    end
  end

  def destroy
    @subscription.fix_suggestion_ignored!
    @subscriptions = current_user.subscriptions.fix_suggestion_present
  end

  def replace_all
    user = current_user

    subscriptions = user
      .subscriptions
      .fix_suggestion_present

    subscriptions.each do |subscription|
      FeedReplacer.perform_async(user.id, subscription.id)
    end

    subscriptions.map(&:fix_suggestion_none!)

    redirect_to settings_subscriptions_url, notice: "Subscriptions successfully replaced."
  end

  private

  def set_subscription
    @subscription = current_user.subscriptions.find(params[:id])
  end

end
