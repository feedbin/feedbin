class Settings::SubscriptionsController < ApplicationController
  def index
    @user = current_user
    @user.setting_off!(:fix_feeds_available)
    @subscriptions = subscriptions_with_sort_data.paginate(page: params[:page], per_page: 50)
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
    destroy_subscription(params[:id])
    redirect_back_or(settings_subscriptions_url, "You have successfully unsubscribed.")
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
        subscriptions = @user.subscriptions
      else
        subscriptions = @user.subscriptions.where(id: params[:subscription_ids])
      end
      if params[:operation] == "unsubscribe"
        subscriptions.destroy_all
        notice = "You have unsubscribed."
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
      if params[:newsletter_sender][:feed_id] == "1"
        @user.subscriptions.create!(feed_id: feed_id)
      else
        @user.subscriptions.where(feed_id: feed_id).take.destroy
      end
    end
    flash[:notice] = "Settings updated."
    flash.discard
  end

  private

  def subscription_params
    params.require(:subscription).permit(:muted, :show_updates, :show_retweets, :media_only, :title)
  end

  def subscriptions_with_sort_data
    dates = @user.subscriptions.order(updated_at: :asc).pluck(:updated_at)
    dates += @user.feeds.includes(:discovered_feeds).map { _1.discovered_feeds.pluck(:updated_at).flatten.sort }
    key = Digest::SHA1.hexdigest(dates.join)

    subscriptions = Rails.cache.fetch("#{@user.id}:subscriptions:#{key}:v8", expires_in: 24.hours) {
      tags = @user.tags_on_feed
      subscriptions = @user
        .subscriptions
        .default
        .select("subscriptions.*, feeds.title AS original_title, feeds.last_published_entry AS last_published_entry, feeds.feed_url, feeds.site_url, feeds.host")
        .joins("INNER JOIN feeds ON subscriptions.feed_id = feeds.id AND subscriptions.user_id = #{@user.id}")
        .includes(feed: [:favicon, :discovered_feeds])
      feed_ids = subscriptions.map(&:feed_id)

      start_date = 29.days.ago

      entry_counts = FeedStat.get_entry_counts(feed_ids, start_date)

      subscriptions.each do |subscription|
        counts = entry_counts[subscription.feed_id]
        percentages = counts.present? ? calculate_percentages(counts) : nil
        volume = counts.present? ? counts.sum : 0

        subscription.title = if subscription.title
          subscription.title
        elsif subscription.original_title
          subscription.original_title
        else
          "(No title)"
        end

        subscription.entries_count = percentages
        subscription.post_volume = volume
        subscription.tag_names = get_tag_names(tags, subscription.feed_id)

        subscription.sort_data = feed_search_data(subscription)
      end
      subscriptions
    }

    if ["updated", "volume", "tag", "name"].include?(params[:sort])
      key = params[:sort].to_sym
      subscriptions = subscriptions.sort_by { |subscription| [subscription.sort_data[key] ? 0 : 1, subscription.sort_data[key]] }
    else
      subscriptions = subscriptions.sort_by { |subscription| subscription.sort_data[:name] }
    end

    if params[:q].present?
      subscriptions = subscriptions.select { |subscription|
        subscription.sort_data[:name].include?(params[:q].downcase)
      }
    end

    subscriptions
  end

  def calculate_percentages(counts)
    max = counts.max.to_i
    counts.map do |count|
      if count == 0
        0.to_f
      else
        count.to_f / max.to_f
      end
    end
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
