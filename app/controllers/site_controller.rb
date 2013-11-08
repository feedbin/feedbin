class SiteController < ApplicationController

  skip_before_action :authorize, only: [:index, :home, :privacy_policy, :apps, :manifest]
  before_action :valid_user, if: :signed_in?

  def index
    if signed_in?
      get_feeds_list
      @user_titles = {}
      @user.feeds.select('feeds.id, feeds.title, subscriptions.title AS user_title').map { |feed|
        @user_titles[feed.id] = feed.user_title ? feed.user_title : feed.title
      }

      @readability_settings = {}
      subscriptions = Subscription.where(user: @user).pluck(:feed_id, :view_inline)
      subscriptions.each { |feed_id, setting| @readability_settings[feed_id] = setting }

      @title = @user.title_with_count

      render action: 'logged_in'
    else
      home
    end
  end

  def home
    @page_view = '/home'
    render action: 'not_logged_in', layout: 'wrap'
  end

  def privacy_policy
    render layout: 'sub_page'
  end

  def apps
    render layout: 'sub_page'
  end

  def manifest; end

  private

  def valid_user
    if current_user.suspended
      redirect_to settings_billing_url, alert: 'Please update your billing information to use Feedbin.'
    end
  end

end
