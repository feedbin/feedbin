class SubscriptionsController < ApplicationController

  before_action :correct_user, only: :destroy

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
      get_feeds_list
    end

    respond_to do |format|
      format.js
    end

  end

  # DELETE /subscriptions/1
  # DELETE /subscriptions/1.json
  def destroy
    @user = current_user
    @subscription = Subscription.find(params[:id])

    # Remove tags on this feed before destorying subscription
    @subscription.feed.tag('', @user)

    # Get rid of the subscription relationship
    @subscription.destroy

    get_feeds_list
    respond_to do |format|
      format.js
    end
  end

  def update_multiple
    @user = current_user
    if params[:unsubscribe]
      if params[:subscription_ids]
        allowed_params = destroy_subscription_params
        subscriptions = Subscription.where(id: allowed_params)
        Tagging.delete_all(user_id: @user, feed_id: subscriptions.map{|subscription| subscription.feed_id})
        subscriptions.destroy_all
      end
      redirect_to settings_feeds_url, notice: "You have unsubscribed."
    else
      allowed_params = subscription_params
      Subscription.update(allowed_params.keys, allowed_params.values)
      redirect_to settings_feeds_url, notice: "Feeds updated."
    end
  end

  private

  def destroy_subscription_params
    owned_subscriptions = @user.subscriptions.pluck(:id)
    params[:subscription_ids].reject {|id| !owned_subscriptions.include?(id.to_i) }
  end

  def subscription_params
    owned_subscriptions = @user.subscriptions.pluck(:id)
    params[:subscriptions].each do |index, fields|
      unless owned_subscriptions.include?(index.to_i)
        params[:subscriptions].delete(index)
      end
    end
    params[:subscriptions].map {|index, fields| params[:subscriptions][index] = fields.slice(:title, :push) }
    params.require(:subscriptions).permit!
  end

  def correct_user
    @subscription = current_user.subscriptions.find_by_id(params[:id])
    render_404 if @subscription.nil?
  end

end
