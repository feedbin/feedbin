class SubscriptionsController < ApplicationController

  # GET subscriptions.xml
  def index
    @user = current_user
    if params[:tag] == "all" || params[:tag].blank?
      @tags = @user.feed_tags
      @feeds = @user.feeds.xml
    else
      @feeds = []
      @tags = Tag.where(id: params[:tag])
    end
    @titles = @user.subscriptions.pluck(:feed_id, :title).each_with_object({}) do |(feed_id, title), hash|
      hash[feed_id] = title
    end
    respond_to do |format|
      format.xml do
        send_data(render_to_string, type: "text/xml", filename: "subscriptions.xml")
      end
    end
  end

  # POST /subscriptions
  # POST /subscriptions.json
  def create
    user = current_user
    valid_feed_ids = Rails.application.message_verifier(:valid_feed_ids).verify(params[:valid_feed_ids])
    @subscriptions = Subscription.create_multiple(params[:feeds].to_unsafe_h, user, valid_feed_ids)
    if @subscriptions.present?
      @click_feed = @subscriptions.first.feed_id
    end
    @mark_selected = true
    get_feeds_list
  end

  # DELETE /subscriptions/1
  # DELETE /subscriptions/1.json
  def destroy
    destroy_subscription(params[:id])
    get_feeds_list
    respond_to do |format|
      format.js
    end
  end

  def feed_destroy
    subscription = @user.subscriptions.where(feed_id: params[:id]).take!
    destroy_subscription(subscription.id)
    get_feeds_list
    respond_to do |format|
      format.js { render "subscriptions/destroy" }
    end
  end

  def update
    @user = current_user
    @subscription = @user.subscriptions.find(params[:id])
    if @subscription.update(subscription_params)
      flash[:notice] = "Settings updated."
    else
      flash[:alert] = "Update failed."
    end
    flash.discard()
  end

  private

  def destroy_subscription(subscription_id)
    @user = current_user
    @subscription = @user.subscriptions.find(subscription_id)
    @subscription.destroy
  end

  def subscription_params
    params.require(:subscription).permit(:muted, :show_updates, :show_retweets, :media_only, :title)
  end
end
