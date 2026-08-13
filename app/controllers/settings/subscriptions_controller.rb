class Settings::SubscriptionsController < ApplicationController
  def index
    @user = current_user
    if @user.setting_on?(:fix_feeds_available)
      @user.setting_off!(:fix_feeds_available)
    end
    # This paginates an Array, so will_paginate validates the page number in
    # the constructor and raises RangeError/ArgumentError rather than returning
    # an empty page. Clamp instead of handing it whatever the URL carried.
    page = [params[:page].to_i, 1].max
    @subscriptions = subscriptions_with_sort_data.paginate(page: page, per_page: 50)
    store_location

    respond_to do |format|
      format.html do
        view = Settings::Subscriptions::IndexView.new(
          user: @user,
          subscriptions: @subscriptions,
          params: params
        )
        render view, layout: "settings"
      end
      # default index.js.erb
      format.js {}
    end
  end

  def destroy
    # prevent_generated_destroy throws :abort, which makes destroy return
    # false rather than raise — so an unconditional success flash told the
    # user a subscription was gone that is still there.
    if destroy_subscription(params[:id])
      flash[:notice] = "You have successfully unsubscribed."
    else
      flash[:alert] = "That subscription can not be removed."
    end
    @redirect = clear_location || settings_subscriptions_url
  end

  def edit
    @user = current_user
    @subscription = @user.subscriptions.find(params[:id])
    render layout: "settings"
  end

  def update
    @user = current_user
    @subscription = @user.subscriptions.find(params[:id])
    if @subscription.update(subscription_params)
      flash[:notice] = "Settings updated."
    else
      flash[:alert] = "Update failed."
    end
    flash.discard
  end

  def refresh_favicon
    @user = current_user
    @subscription = @user.subscriptions.find(params[:id])
    FaviconCrawler::Finder.perform_async(@subscription.feed.host)
    flash[:notice] = "Favicon will be refreshed shortly"
    flash.discard
    render "settings/subscriptions/update"
  end

  def update_multiple
    @user = current_user
    notice = "Feeds updated."
    if params[:operation] && params[:subscription_ids] || params[:include_all]
      if params[:include_all] && params[:q].present?
        ids = subscriptions_with_sort_data.map(&:id)
        subscriptions = @user.subscriptions.where(id: ids)
      elsif params[:include_all]
        # The checkbox summarises the list on screen, which is the default
        # scope — not every row the association holds.
        subscriptions = @user.subscriptions.default
      else
        subscriptions = @user.subscriptions.where(id: params[:subscription_ids])
      end
      if params[:operation] == "unsubscribe"
        selected = subscriptions.count
        removed = subscriptions.destroy_all.count(&:destroyed?)
        notice = if removed == selected
          "You have unsubscribed."
        elsif removed.zero?
          "None of those subscriptions could be removed."
        else
          "Unsubscribed from #{removed} of #{selected} feeds."
        end
      elsif params[:operation] == "show_updates"
        subscriptions.update_all(show_updates: true, updated_at: Time.now)
      elsif params[:operation] == "hide_updates"
        subscriptions.update_all(show_updates: false, updated_at: Time.now)
      elsif params[:operation] == "mute"
        subscriptions.update_all(muted: true, updated_at: Time.now)
      elsif params[:operation] == "unmute"
        subscriptions.update_all(muted: false, updated_at: Time.now)
      end
    end
    redirect_to settings_subscriptions_url, notice: notice
  end

  def newsletter_senders
    @user = current_user
    valid = @user.newsletter_senders.pluck(:feed_id)
    feed_id = params[:id].to_i
    if valid.include?(feed_id)
      Subscription.set_subscribed(@user, feed_id, params[:newsletter_sender][:feed_id] == "1")
    end
    flash[:notice] = "Settings updated."
    flash.discard
  end

  private

  def subscription_params
    params.require(:subscription).permit(:muted, :show_updates, :show_retweets, :media_only, :title)
  end

  def subscriptions_with_sort_data
    tags = @user.tags_on_feed
    subscriptions = @user
      .subscriptions
      .default
      .select("subscriptions.*, feeds.title AS original_title, feeds.last_published_entry AS last_published_entry, feeds.feed_url, feeds.site_url, feeds.host")
      .joins("INNER JOIN feeds ON subscriptions.feed_id = feeds.id AND subscriptions.user_id = #{@user.id}")
      .includes(feed: [:favicon, :icon_image_record, :discovered_feeds])
    feed_ids = subscriptions.map(&:feed_id)

    start_date = 29.days.ago

    entry_counts = FeedStat.daily_counts(feed_ids: feed_ids)

    subscriptions.each do |subscription|
      counts = entry_counts[subscription.feed_id]

      subscription.title = if subscription.title
        subscription.title
      elsif subscription.original_title
        subscription.original_title
      else
        "(No title)"
      end

      subscription.entries_count = counts&.percentages
      subscription.post_volume = counts&.volume
      subscription.tag_names = get_tag_names(tags, subscription.feed_id)

      subscription.sort_data = feed_search_data(subscription)
    end

    if ["updated", "volume", "tag", "name"].include?(params[:sort])
      key = params[:sort].to_sym
      subscriptions = subscriptions.sort_by { |subscription| [subscription.sort_data[key] ? 0 : 1, subscription.sort_data[key]] }
    else
      subscriptions = subscriptions.sort_by { |subscription| subscription.sort_data[:name] }
    end

    if params[:q].present?
      parts = params[:q].downcase.split
      subscriptions = subscriptions.select { |subscription|
        parts.all? { |part| subscription.sort_data[:name].include?(part) }
      }
    end

    subscriptions
  end

  def feed_search_data(subscription)
    name = [].tap do |array|
      array.push subscription.title.downcase
      array.push subscription.site_url
      array.push subscription.feed_url
      array.push subscription.muted_status
      array.push subscription.health_status
      array.push subscription.tag_names
      if subscription.feed.newsletter?
        array.push "newsletter"
      end
    end.compact.join

    {
      name: name.downcase,
      tag: subscription.tag_names,
      updated: -(subscription.try(:last_published_entry).try(:to_time).try(:to_i) || 0),
      volume: -subscription.post_volume
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
