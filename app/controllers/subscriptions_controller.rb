class SubscriptionsController < ApplicationController

  # GET subscriptions.xml
  def index
    @user = current_user
    @tags = @user.feed_tags
    @feeds = @user.feeds
    @titles = {}
    @user.subscriptions.pluck(:feed_id, :title).each do |feed_id, title|
      @titles[feed_id] = title
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
    else
      allowed_params = subscription_params
      Subscription.update(allowed_params.keys, allowed_params.values)
    end
    redirect_to settings_feeds_url, notice: notice
  end

  def destroy_all
    @user = current_user
    @user.subscriptions.destroy_all
    redirect_to settings_feeds_url, notice: "You have unsubscribed."
  end

  def toggle_updates
    user = current_user
    subscription = user.subscriptions.find(params[:id])
    subscription.toggle!(:show_updates)
    render nothing: true
  end

  def toggle_muted
    user = current_user
    subscription = user.subscriptions.find(params[:id])
    subscription.toggle!(:muted)
    render nothing: true
  end

  private

  def subscription_params
    owned_subscriptions = @user.subscriptions.pluck(:id)
    params[:subscriptions].each do |index, fields|
      unless owned_subscriptions.include?(index.to_i)
        params[:subscriptions].delete(index)
      end
    end
    params[:subscriptions].map do |index, fields|
      params[:subscriptions][index] = fields.slice(:title, :push)
    end

    params.require(:subscriptions).permit!
  end

end
