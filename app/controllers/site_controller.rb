class SiteController < ApplicationController

  skip_before_action :authorize, only: [:index, :home, :privacy_policy, :apps, :manifest]
  before_action :check_user, if: :signed_in?

  def index
    if signed_in?
      get_feeds_list
      subscriptions = @user.subscriptions

      user_titles = subscriptions.each_with_object({}) do |subscription, hash|
        if subscription.title.present?
          hash[subscription.feed_id] = subscription.title
        end
      end

      readability_settings = subscriptions.each_with_object({}) do |subscription, hash|
        hash[subscription.feed_id] = subscription.view_inline
      end

      @show_welcome = (subscriptions.present?) ? false : true
      @data = {
        login_url: login_url,
        tags_path: tags_path(format: :json),
        user_titles: user_titles,
        preload_entries_path: preload_entries_path(format: :json),
        sticky_readability: (@user.sticky_view_inline == '1'),
        readability_settings: readability_settings,
        show_unread_count:  (@user.show_unread_count == '1'),
        precache_images: (@user.precache_images == '1'),
        auto_update_path: auto_update_feeds_path,
        font_sizes: Feedbin::Application.config.font_sizes,
        mark_as_read_path: mark_all_as_read_entries_path,
        mark_as_read_confirmation: (@user.mark_as_read_confirmation == '1'),
        mark_direction_as_read_entries: mark_direction_as_read_entries_path,
        entry_sort: @user.entry_sort
      }

      render action: 'logged_in'
    else
      home
    end
  end

  def home
    @page_view = '/home'
    render action: 'not_logged_in'
  end

  def privacy_policy
    render layout: 'sub_page'
  end

  def apps
    render layout: 'sub_page'
  end

  def manifest; end

  private

  def check_user
    if current_user.suspended
      redirect_to settings_billing_url, alert: 'Please update your billing information to use Feedbin.'
    end
  end

end
