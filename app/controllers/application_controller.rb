class ApplicationController < ActionController::Base
  # Prevent CSRF attacks by raising an exception.
  # For APIs, you may want to use :null_session instead.
  protect_from_forgery with: :exception
  include SessionsHelper

  before_action :authorize
  before_action :set_user
  before_action :honeybadger_context
  after_action :set_csrf_cookie

  etag { current_user.try :id }

  add_flash_types :one_time_content

  def append_info_to_payload(payload)
    super
    payload[:feedbin_request_id] = request.headers["X-Feedbin-Request-ID"]
    payload[:request_start] = request.headers["X-Request-Start"]
  end

  def render_404
    respond_to do |format|
      format.any do
        render "errors/not_found.html.erb", layout: nil, status: :not_found, content_type: "text/html"
      end
    end
  end

  def logged_in
    get_feeds_list
    subscriptions = @user.subscriptions

    user_titles = subscriptions.each_with_object({}) { |subscription, hash|
      if subscription.title.present?
        hash[subscription.feed_id] = ERB::Util.html_escape_once(subscription.title)
      end
    }

    readability_settings = {}
    subscription_view_settings = {}
    subscriptions.each do |subscription|
      readability_settings[subscription.feed_id] = subscription.view_inline
      subscription_view_settings[subscription.feed_id] = subscription.view_mode
    end

    @now_playing = Entry.where(id: @user.now_playing_entry).first
    @recently_played = @user.recently_played_entries.where(entry_id: @user.now_playing_entry).first

    @show_welcome = subscriptions.present? ? false : true
    @update_ids = @user.subscriptions.where(show_updates: false).pluck(:feed_id).map { |feed_id| ".entry-feed-#{feed_id} .diff-wrap" }.join(", ")
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
      audio_panel_size: @user.audio_panel_size,
      view_links_in_app: @user.setting_on?(:view_links_in_app),
      saved_searches_count_path: count_saved_searches_path,
      proxy_images: !@user.setting_on?(:disable_image_proxy),
      twitter_embed_path: twitter_embeds_path,
      instagram_embed_path: instagram_embeds_path,
      favicon_colors: @user.setting_on?(:favicon_colors),
      font_stylesheet: ENV["FONT_STYLESHEET"],
      modal_extracts_path: modal_extracts_path,
      progress: @user.recently_played_entries_progress,
      subscription_view_mode: subscription_view_settings,
      pages_internal_path: pages_internal_path,
      tag_visibility: @user.tag_visibility,
      visibility_key: "tag_visibility"
    }

    render "site/logged_in"
  end

  def get_collections
    user = current_user
    collections = []
    collections << {
      title: "Unread",
      path: unread_entries_path,
      count_data: {behavior: "needs_count", count_group: "all"},
      id: "collection_unread",
      favicon_class: "favicon-unread",
      favicon_alt_class: "favicon-unread-active",
      parent_class: "collection-unread",
      parent_data: {behavior: "all_unread", feed_id: "collection_unread", count_type: "unread"},
      data: {behavior: "selectable show_entries open_item feed_link", mark_read: {type: "unread", message: "Mark all items as read?"}.to_json}
    }
    collections << {
      title: "All",
      path: entries_path,
      count_data: {behavior: "needs_count", count_group: "all"},
      id: "collection_all",
      favicon_class: "favicon-all",
      parent_class: "collection-all",
      parent_data: {behavior: "all_unread", feed_id: "collection_all", count_type: "unread"},
      data: {behavior: "selectable show_entries open_item feed_link", mark_read: {type: "all", message: "Mark all items as read?"}.to_json}
    }
    collections << {
      title: "Starred",
      path: starred_entries_path,
      count_data: {behavior: "needs_count", count_group: "all"},
      id: "collection_starred",
      favicon_class: "favicon-star",
      parent_class: "collection-starred",
      parent_data: {behavior: "starred", feed_id: "collection_starred", count_type: "starred"},
      data: {behavior: "selectable show_entries open_item feed_link", mark_read: {type: "starred", message: "Mark starred items as read?"}.to_json}
    }
    unless user.setting_on?(:hide_recently_read)
      collections << {
        title: "Recently Read",
        path: recently_read_entries_path,
        count_data: nil,
        id: "collection_recently_read",
        favicon_class: "favicon-recently-read",
        parent_class: "collection-recently-read",
        parent_data: {behavior: "recently_read", feed_id: "collection_recently_read", count_type: "recently_read"},
        data: {behavior: "selectable show_entries open_item feed_link", mark_read: {type: "recently_read", message: "Mark recently read items as read?"}.to_json},
        clear: {path: destroy_all_recently_read_entries_path, message: "Clear all recently read?"}
      }
    end
    unless user.setting_on?(:hide_updated)
      collections << {
        title: "Updated",
        path: updated_entries_path,
        count_data: {behavior: "needs_count", count_group: "all", count_collection: "updated", count_hide: "on"},
        id: "collection_updated",
        favicon_class: "favicon-updated",
        parent_class: "collection-updated",
        parent_data: {behavior: "updated", feed_id: "collection_updated", count_type: "updated"},
        data: {behavior: "selectable show_entries open_item feed_link", special_collection: "updated", mark_read: {type: "updated", message: "Mark updated items as read?"}.to_json}
      }
    end
    unless user.setting_on?(:hide_recently_played)
      collections << {
        title: "Recently Played",
        path: recently_played_entries_path,
        count_data: nil,
        id: "collection_recently_played",
        favicon_class: "favicon-recently-played",
        parent_class: "collection-recently-played",
        parent_data: {behavior: "recently_played", feed_id: "collection_recently_played", count_type: "recently_played"},
        data: {behavior: "selectable show_entries open_item feed_link", mark_read: {type: "recently_played", message: "Mark recently played items as read?"}.to_json},
        clear: {path: destroy_all_recently_played_entries_path, message: "Clear all recently played?"}
      }
    end
    collections
  end

  def get_feeds_list
    @user = current_user
    @page_feed = @user.feeds.pages.first

    excluded_feeds = @user.taggings.distinct.pluck(:feed_id)
    excluded_feeds += [@page_feed&.id]
    @feeds = @user.feeds.where.not(id: excluded_feeds).includes(:favicon)

    @count_data = {
      unread_entries: @user.unread_entries.pluck("feed_id, entry_id").each_slice(10_000).to_a,
      starred_entries: @user.starred_entries.pluck("feed_id, entry_id").each_slice(10_000).to_a,
      updated_entries: @user.updated_entries.pluck("feed_id, entry_id").each_slice(10_000).to_a,
      tag_map: @user.taggings.build_tag_map,
      feed_map: @user.taggings.build_feed_map,
      entry_sort: @user.entry_sort
    }
    @feed_data = {
      feeds: @feeds,
      page_feed: @page_feed,
      collections: get_collections,
      tags: @user.tag_group,
      saved_searches: @user.saved_searches.order(Arel.sql("lower(name)")),
      count_data: @count_data,
      feed_order: @user.feed_order
    }
  end

  def render_file_or(file, status, &block)
    if ENV["SITE_PATH"].present? && File.exist?(File.join(ENV["SITE_PATH"], file))
      render file: File.join(ENV["SITE_PATH"], file), status: status, layout: nil
    else
      yield
    end
  end

  def set_csrf_cookie
    cookies["XSRF-TOKEN"] = form_authenticity_token if protect_against_forgery?
  end

  protected

  def verified_request?
    super || valid_authenticity_token?(session, request.headers["X-XSRF-TOKEN"])
  end

  private

  def set_user
    @user = current_user
  end

  def feeds_response
    view_mode = params[:view] || params[:view_mode]
    if view_mode == "view_all"
      entry_id_cache = EntryIdCache.new(@user.id, @feed_ids)
      @entries = entry_id_cache.page(params[:page])
      @page_query = @entries
    elsif view_mode == "view_starred"
      starred_entries = @user.starred_entries.select(:entry_id).where(feed_id: @feed_ids).page(params[:page]).order("published DESC")
      @entries = Entry.entries_with_feed(starred_entries, "DESC").entries_list
      @page_query = starred_entries
    else
      @all_unread = "true"
      unread_entries = @user.unread_entries.select(:entry_id).where(feed_id: @feed_ids).page(params[:page]).sort_preference(@user.entry_sort)
      @entries = Entry.entries_with_feed(unread_entries, @user.entry_sort).entries_list
      @page_query = unread_entries
    end
  end

  def honeybadger_context
    Honeybadger.context(user_id: current_user.id) if current_user
  end

  def verify_push_token(authentication_token)
    authentication_token = CGI.unescape(authentication_token)
    verifier = ActiveSupport::MessageVerifier.new(Rails.application.secrets.secret_key_base)
    verifier.verify(authentication_token)
  end
end
