class SiteController < ApplicationController
  skip_before_action :authorize, only: [:index]
  before_action :check_user, if: :signed_in?

  def index
    if signed_in?
      get_feeds_list
      subscriptions = @user.subscriptions

      user_titles = subscriptions.each_with_object({}) { |subscription, hash|
        if subscription.title.present?
          hash[subscription.feed_id] = ERB::Util.html_escape_once(subscription.title)
        end
      }

      readability_settings = subscriptions.each_with_object({}) { |subscription, hash|
        hash[subscription.feed_id] = subscription.view_inline
      }

      @now_playing = Entry.where(id: @user.now_playing_entry).first
      @recently_played = @user.recently_played_entries.where(entry_id: @user.now_playing_entry).first

      @show_welcome = subscriptions.present? ? false : true
      @classes = user_classes
      @data = {
        login_url: login_url,
        tags_path: tags_path(format: :json),
        user_titles: user_titles,
        preload_entries_path: preload_entries_path(format: :json),
        sticky_readability: @user.setting_on?(:sticky_view_inline),
        readability_settings: readability_settings,
        show_unread_count: @user.setting_on?(:show_unread_count),
        precache_images: @user.setting_on?(:precache_images),
        auto_update_path: auto_update_feeds_path,
        font_sizes: Feedbin::Application.config.font_sizes,
        mark_as_read_path: mark_all_as_read_entries_path,
        mark_as_read_confirmation: @user.setting_on?(:mark_as_read_confirmation),
        mark_direction_as_read_entries: mark_direction_as_read_entries_path,
        entry_sort: @user.entry_sort,
        update_message_seen: @user.setting_on?(:update_message_seen),
        feed_order: @user.feed_order,
        refresh_sessions_path: refresh_sessions_path,
        progress: {},
        audio_panel_size: @user.audio_panel_size,
        view_links_in_app: @user.setting_on?(:view_links_in_app),
        saved_searches_count_path: count_saved_searches_path,
        proxy_images: !@user.setting_on?(:disable_image_proxy),
        twitter_embed_path: twitter_embeds_path,
        instagram_embed_path: instagram_embeds_path,
        theme: @user.theme || "day",
        favicon_colors: @user.setting_on?(:favicon_colors),
        font_stylesheet: ENV["FONT_STYLESHEET"],
        modal_extracts_path: modal_extracts_path,
        settings_view_mode_path: settings_view_mode_path,
      }

      render action: "logged_in"
    else
      render_file_or("home/index.html", :ok) {
        redirect_to login_url
      }
    end
  end

  def subscribe
    redirect_to root_url(request.query_parameters)
  end

  def headers
    @user = current_user
    if @user.admin?
      @headers = request.env.select { |k, v| k =~ /^HTTP_/ }
    end
  end

  private

  def check_user
    if current_user.suspended
      redirect_to settings_billing_url, alert: "Please update your billing information to use Feedbin."
    end
  end
end
