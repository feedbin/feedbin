class Settings::SubscriptionsController < ApplicationController

  def index
    @user = current_user
    @subscriptions = @user.subscriptions.select('subscriptions.*, feeds.title AS original_title, feeds.last_published_entry AS last_published_entry, feeds.feed_url, feeds.site_url, feeds.host').joins("INNER JOIN feeds ON subscriptions.feed_id = feeds.id AND subscriptions.user_id = #{@user.id}").includes(feed: [:favicon])
    @tags = @user.tags_on_feed
    start_date = 29.days.ago
    feed_ids = @subscriptions.map {|subscription| subscription.feed_id}
    entry_counts = Rails.cache.fetch("#{@user.id}:entry_counts:2", expires_in: 24.hours) { FeedStat.get_entry_counts(feed_ids, start_date) }

    @subscriptions = @subscriptions.map do |subscription|
      counts = entry_counts[subscription.feed_id]
      max = (counts.present?) ? counts.max.to_i : 0
      percentages = (counts.present?) ? counts.map { |count| count.to_f / max.to_f } : nil
      volume = (counts.present?) ? counts.sum : 0

      subscription.entries_count = percentages
      subscription.post_volume = volume

      if subscription.title
        subscription.title = subscription.title
      elsif subscription.original_title
        subscription.title = subscription.original_title
      else
        subscription.title = '(No title)'
      end
      subscription
    end

    @subscriptions = @subscriptions.sort_by {|subscription| subscription.title.downcase}
    render layout: "settings"
  end

  def destroy
    destroy_subscription(params[:id])
    redirect_to settings_subscriptions_url, notice: 'You have successfully unsubscribed.'
  end

  def edit
    @user = current_user
    @subscription = @user.subscriptions.find(params[:id])
    render layout: "settings"
  end

  def refresh_favicon
    @user = current_user
    @subscription = @user.subscriptions.find(params[:id])
    FaviconFetcher.perform_async(@subscription.feed.host)
    flash[:notice] = "Favicon will be refreshed shortly"
    flash.discard()
    render 'subscriptions/update'
  end

  def update_multiple
    @user = current_user
    notice = "Feeds updated."
    if params[:operation] && params[:subscription_ids]
      subscriptions = @user.subscriptions.where(id: params[:subscription_ids])
      if params[:operation] == "unsubscribe"
        subscriptions.destroy_all
        notice = "You have unsubscribed."
      elsif params[:operation] == "show_updates"
        subscriptions.update_all(show_updates: true)
      elsif params[:operation] == "hide_updates"
        subscriptions.update_all(show_updates: false)
      elsif params[:operation] == "mute"
        subscriptions.update_all(muted: true)
      elsif params[:operation] == "unmute"
        subscriptions.update_all(muted: false)
      end
    end
    redirect_to settings_subscriptions_url, notice: notice
  end

  private

  def feed_search_data(subscription, tags)
    subscription.title.downcase +
    subscription.site_url +
    subscription.feed_url +
    get_tag_names(tags, subscription.feed_id) +
    subscription.muted_status
  end

  def get_tag_names(tags, feed_id)
    if names = tags[feed_id]
      names.join(", ")
    end
  end

  def destroy_subscription(subscription_id)
    @user = current_user
    @subscription = @user.subscriptions.find(subscription_id)
    @subscription.destroy
  end

end

