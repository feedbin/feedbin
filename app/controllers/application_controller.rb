class ApplicationController < ActionController::Base
  # Prevent CSRF attacks by raising an exception.
  # For APIs, you may want to use :null_session instead.
  protect_from_forgery with: :exception
  include SessionsHelper

  before_action :authorize
  before_action :set_view_mode
  before_action :honeybadger_context
  before_action :block_if_maintenance_mode

  etag { current_user.try :id }

  add_flash_types :analytics_event

  def update_selected_feed!(type, data = nil)
    if data.nil?
      selected_feed = type
    else
      session[:selected_feed_data] = data
      selected_feed = "#{type}_#{data}"
    end
    session[:selected_feed_type] = type
    session[:selected_feed] = selected_feed
  end

  def render_404
    render 'errors/not_found', status: 404, layout: 'application', formats: [:html]
  end

  def get_collections(*types, count)
    @user = current_user
    types = [*types]
    collections = []
    if types.include? 'view_unread'
      collections << {
        title: 'Unread',
        path: unread_entries_path,
        count: count,
        id: 'collection_unread',
        favicon_class: 'favicon-unread',
        parent_data: { behavior: 'all_unread', feed_id: 'collection_unread' },
        data: { behavior: 'selectable reset_entry_position show_entries open_item feed_link', mark_read: {type: 'unread', message: 'Mark all items as read?'}.to_json }
      }
    end
    if types.include? 'view_all'
      collections << {
        title: 'All',
        path: entries_path,
        count: count,
        id: 'collection_all',
        favicon_class: 'favicon-all',
        parent_data: { behavior: 'all_unread', feed_id: 'collection_all' },
        data: { behavior: 'selectable reset_entry_position show_entries open_item feed_link', mark_read: {type: 'all', message: 'Mark all items as read?'}.to_json }
      }
    end
    collections << {
      title: 'Starred',
      path: starred_entries_path,
      count: @user.total_starred,
      id: 'collection_starred',
      favicon_class: 'favicon-star',
      parent_data: { behavior: 'starred', feed_id: 'collection_starred' },
      data: { behavior: 'selectable reset_entry_position show_entries open_item feed_link', mark_read: {type: 'starred', message: 'Mark starred items as read?'}.to_json }
    }
    collections
  end

  def get_feeds_list
    @mark_selected = true
    @user = current_user

    if @user.hide_tagged_feeds == '1'
      excluded_feeds = @user.taggings.pluck(:feed_id).uniq
      @feeds = @user.feeds.where.not(id: excluded_feeds).include_user_title
    else
      @feeds = @user.feeds.include_user_title
    end

    @feeds = @user.feed_count(session[:view_mode], @feeds, session[:selected_feed], @keep_selected)
    @collections = get_collections(session[:view_mode], @user.total_unread)
    @tags = @user.owned_tags_with_count(session[:view_mode], session[:selected_feed], @keep_selected)
    @saved_searches = @user.saved_searches.order("lower(name)")
  end

  private

  def update_with_state(entries)
    user = current_user
    entry_ids = entries.map {|entry| entry.id }
    unread = user.unread_entries.where(entry_id: entry_ids).pluck(:entry_id)
    starred = user.starred_entries.where(entry_id: entry_ids).pluck(:entry_id)
    entries.each_with_index do |entry, index|
      if unread.include?(entry.id)
        entries[index].read = false
      else
        entries[index].read = true
      end
      if starred.include?(entry.id)
        entries[index].starred = true
      else
        entries[index].starred = false
      end
    end
    entries
  end

  def feeds_response
    if 'view_all' == session[:view_mode]
      # Get all entries 100 at a time, then get unread info
      @entries = Entry.where(feed_id: @feed_ids).page(params[:page]).includes(:feed).sort_preference(@user.entry_sort)
    else
      # Get unread info, then get entries
      unread_entries = @user.unread_entries.select(:entry_id).where(feed_id: @feed_ids).page(params[:page]).sort_preference(@user.entry_sort)
      @entries = Entry.entries_with_feed(unread_entries, @user.entry_sort)
    end

    @entries = update_with_state(@entries)
    if 'view_all' == session[:view_mode]
      @page_query = @entries
    else
      @page_query = unread_entries
    end
  end

  def set_view_mode
    session[:view_mode] ||= 'view_unread'
  end

  def block_if_maintenance_mode
    if ENV['FEEDBIN_MAINTENANCE_MODE']
      if request.format.json?
        render status: 503, json: {message: 'The site is undergoing maintenance.'}
      else
        render 'errors/service_unavailable', status: 503, layout: 'application'
      end
    end
  end

  def honeybadger_context
    Honeybadger.context(user_id: current_user.id) if current_user
  end

  def verify_push_token(authentication_token)
    authentication_token = CGI::unescape(authentication_token)
    verifier = ActiveSupport::MessageVerifier.new(Feedbin::Application.config.secret_key_base)
    verifier.verify(authentication_token)
  end

end
