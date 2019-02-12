class SubscriptionsController < ApplicationController

  def index
    @user = current_user
    if params[:tag] == "all" || params[:tag].blank?
      @tags = @user.feed_tags
      @feeds = @user.feeds.xml
    else
      @feeds = []
      @tags = Tag.where(id: params[:tag])
    end
    @titles = @user.subscriptions.pluck(:feed_id, :title).each_with_object({}) { |(feed_id, title), hash|
      hash[feed_id] = title
    }
    respond_to do |format|
      format.xml do
        send_data(render_to_string, type: "text/xml", filename: "subscriptions.xml")
      end
    end
  end

  def create
    user = current_user
    valid_feed_ids = Rails.application.message_verifier(:valid_feed_ids).verify(params[:valid_feed_ids])
    @subscriptions = Subscription.create_multiple(params[:feeds].to_unsafe_h, user, valid_feed_ids)
    if @subscriptions.present?
      @subscriptions.each do |subscription|
        subscription.feed.tag_with_params(params, user)
      end
      @click_feed = @subscriptions.first.feed_id
    end
    @mark_selected = true
    get_feeds_list
  end

  def edit
    @user = current_user
    @subscription = @user.subscriptions.find_by_feed_id(params[:id])
    @tag_editor = TagEditor.new(@user, @subscription.feed)
    render layout: "settings"
  end

  def update
    @user = current_user
    @mark_selected = false
    @subscription = @user.subscriptions.find(params[:id])
    @subscription.update(subscription_params)
    @taggings = @subscription.feed.tag_with_params(params, @user)
    if @taggings.present?
      @user.update_tag_visibility(@taggings.first.tag.id.to_s, true)
    end
    get_feeds_list
  end

  def destroy
    subscription = @user.subscriptions.find(params[:id])
    destroy_subscription(subscription.id)
    get_feeds_list
  end

  private

  def destroy_subscription(subscription_id)
    @user = current_user
    @subscription = @user.subscriptions.find(subscription_id)
    @subscription.destroy
  end

  def subscription_params
    params.require(:subscription).permit(:title)
  end
end
