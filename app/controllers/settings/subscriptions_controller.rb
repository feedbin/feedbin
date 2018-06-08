class Settings::SubscriptionsController < ApplicationController

  def index
    @user = current_user
    @subscriptions = @user.subscriptions.select('subscriptions.*, feeds.title AS original_title, feeds.last_published_entry AS last_published_entry, feeds.feed_url, feeds.site_url, feeds.host').joins("INNER JOIN feeds ON subscriptions.feed_id = feeds.id AND subscriptions.user_id = #{@user.id}").includes(feed: [:favicon])
    @tags = @user.tags_on_feed
    start_date = 29.days.ago
    feed_ids = @subscriptions.map(&:feed_id)
    entry_counts = Rails.cache.fetch("#{@user.id}:entry_counts:2", expires_in: 24.hours) { FeedStat.get_entry_counts(feed_ids, start_date) }

    @subscriptions = @subscriptions.map do |subscription|
      counts = entry_counts[subscription.feed_id]
      max = (counts.present?) ? counts.max.to_i : 0
      percentages = (counts.present?) ? counts.map { |count| count.to_f / max.to_f } : nil
      volume = (counts.present?) ? counts.sum : 0

      if subscription.title
        subscription.title = subscription.title
      elsif subscription.original_title
        subscription.title = subscription.original_title
      else
        subscription.title = '(No title)'
      end

      subscription.entries_count = percentages
      subscription.post_volume = volume
      subscription.sort_data = feed_search_data(subscription, @tags)

      subscription
    end

    case params[:sort]
    when "updated"
      @subscriptions = @subscriptions.sort_by {|subscription| subscription.sort_data[:updated]}.reverse
    when "volume"
      @subscriptions = @subscriptions.sort_by {|subscription| subscription.sort_data[:volume]}.reverse
    when "tags"
      @subscriptions = @subscriptions.sort_by {|subscription| subscription.sort_data[:tags]}
    else
      if params[:sort]
        @subscriptions = @subscriptions.each do |subscription|
          subscription.sort_data[:score] = subscription.sort_data[:name].score(params[:sort])
        end
        @subscriptions = @subscriptions.reject do |subscription|
          subscription.sort_data[:score] == 0
        end
        @subscriptions = @subscriptions.sort_by {|subscription| subscription.sort_data[:score] }.reverse
      else
        @subscriptions = @subscriptions.sort_by {|subscription| subscription.sort_data[:name] }
      end
    end

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
    tag_names = get_tag_names(tags, subscription.feed_id)

    name = Array.new.tap do |array|
      array.push subscription.title.downcase
      array.push subscription.site_url
      array.push subscription.feed_url
      array.push subscription.muted_status
      array.push tag_names
    end.compact.join

    {
      name: name,
      updated: subscription.try(:last_published_entry).try(:to_time).try(:to_i),
      volume: subscription.post_volume,
      tags: tag_names,
    }
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

