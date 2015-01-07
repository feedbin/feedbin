class SubscriptionsController < ApplicationController

  # GET subscriptions.xml
  def index
    @user = current_user
    if params[:tag] == 'all' || params[:tag].blank?
      @tags = @user.feed_tags
      @feeds = @user.feeds
    else
      @feeds = []
      @tags = Tag.where(id: params[:tag])
    end
    @titles = @user.subscriptions.pluck(:feed_id, :title).each_with_object({}) do |(feed_id, title), hash|
      hash[feed_id] = title
    end
    respond_to do |format|
      format.xml do
        send_data(render_to_string, type: 'text/xml', filename: 'subscriptions.xml')
      end
    end
  end

  # POST /subscriptions
  # POST /subscriptions.json
  def create
    @user = current_user

    feeds = [*params[:subscription][:feeds][:feed_url]]
    site_url = params[:subscription][:site_url]
    @results = { success: [], options: [], failed: [] }

    feeds.each do |feed|
      begin
        result = FeedFetcher.new(feed, site_url).create_feed!
        if result.feed
          @user.safe_subscribe(result.feed)
          @results[:success].push(result.feed)
        elsif result.feed_options.any?
          @results[:options].push(result.feed_options)
        else
          @results[:failed].push(feed)
        end
      rescue Exception => e
        logger.info { e.inspect }
        Honeybadger.notify(e)
        @results[:failed].push(feed)
      end
    end

    if @results[:success].any?
      session[:favicon_complete] = false
      @mark_selected = true
      @click_feed = @results[:success].first.id
      @favicon_hash = UpdateFaviconHash.new.get_hash(@user)
      get_feeds_list
    end

    respond_to do |format|
      format.js
    end

  end

  # DELETE /subscriptions/1
  # DELETE /subscriptions/1.json
  def destroy
    destroy_subscription
    get_feeds_list
    respond_to do |format|
      format.js
    end
  end

  def settings_destroy
    destroy_subscription
    redirect_to settings_feeds_url, notice: 'You have successfully unsubscribed.'
  end

  def destroy_subscription
    @user = current_user
    @subscription = @user.subscriptions.find(params[:id])
    @subscription.destroy
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
    redirect_to settings_feeds_url, notice: notice
  end

  def destroy_all
    @user = current_user
    @user.subscriptions.destroy_all
    redirect_to settings_feeds_url, notice: "You have unsubscribed."
  end

end
