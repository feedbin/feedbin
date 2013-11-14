class EntriesController < ApplicationController

  skip_before_action :verify_authenticity_token, only: [:push_view]
  skip_before_action :authorize, only: [:push_view]

  def index
    @user = current_user
    update_selected_feed!("collection_all")

    @entries = @user.entries.page(params[:page]).includes(:feed).sort_preference(@user.entry_sort)
    @entries = update_with_state(@entries)
    @page_query = @entries

    @append = !params[:page].nil?

    @type = 'all'
    @data = nil

    @collection_title = 'All'
    @collection_favicon = 'favicon-all'

    respond_to do |format|
      format.js { render partial: 'shared/entries' }
    end
  end

  def unread
    @user = current_user
    update_selected_feed!('collection_unread')

    unread_entries = @user.unread_entries.select(:entry_id).page(params[:page]).sort_preference(@user.entry_sort)
    @entries = Entry.entries_with_feed(unread_entries, @user.entry_sort)

    @entries = update_with_state(@entries)
    @page_query = unread_entries

    @append = params[:page].present?

    @type = 'unread'
    @data = nil

    @collection_title = 'Unread'
    @collection_favicon = 'favicon-unread'

    respond_to do |format|
      format.js { render partial: 'shared/entries' }
    end
  end

  def starred
    @user = current_user
    update_selected_feed!("collection_starred")

    starred_entries = @user.starred_entries.select(:entry_id).page(params[:page]).sort_preference(@user.entry_sort)
    @entries = Entry.entries_with_feed(starred_entries, @user.entry_sort)

    @entries = update_with_state(@entries)
    @page_query = starred_entries

    @append = params[:page].present?

    @type = 'starred'
    @data = nil

    @collection_title = 'Starred'
    @collection_favicon = 'favicon-star'

    respond_to do |format|
      format.js { render partial: 'shared/entries' }
    end
  end

  def show
    @user = current_user
    @entry = Entry.find params[:id]

    @content_view = false
    if @user.sticky_view_inline == '1'
      subscription = Subscription.where(user: @user, feed_id: @entry.feed_id).first

      # Subscription will not necessarily be present for starred items
      if subscription.try(:view_inline)
        @content_view = true
        view_inline
        @entry.content = @content
      end
    end

    @decrement = UnreadEntry.where(user_id: @user.id, entry_id: @entry.id).delete_all > 0 ? true : false

    @read = true
    @starred = StarredEntry.where(user_id: @user.id, entry_id: @entry.id).present?
    @feed = @entry.feed
    @tags = @user.tags.where(taggings: {feed_id: @feed}).uniq.collect(&:id)

    @services = sharing_services(@entry)
    respond_to do |format|
      format.js
    end
  end

  def content
    @user = current_user
    @entry = Entry.find params[:id]

    if 'true' == params[:content_view]
      @content_view = true
    else
      @content_view = false
    end

    if @user.sticky_view_inline == '1'
      subscription = Subscription.where(user: @user, feed_id: @entry.feed_id).first
      if subscription.present?
        subscription.update_attributes(view_inline: @content_view)
      end
    end

    view_inline
    @content = ContentFormatter.format!(@content, @entry)

  end

  def mark_all_as_read
    @user = current_user

    if params[:type] == 'feed'
      UnreadEntry.where(user_id: @user.id, feed_id: params[:data]).delete_all
    elsif params[:type] == 'tag'
      feed_ids = @user.taggings.where(tag_id: params[:data]).pluck(:feed_id)
      UnreadEntry.where(user_id: @user.id, feed_id: feed_ids).delete_all
    elsif params[:type] == 'starred'
      starred = @user.starred_entries.pluck(:entry_id)
      UnreadEntry.where(user_id: @user.id, entry_id: starred).delete_all
    elsif  %w{unread all}.include?(params[:type])
      UnreadEntry.where(user_id: @user.id).delete_all
    elsif params[:type] == 'saved_search'
      saved_search = @user.saved_searches.where(id: params[:data]).first
      if saved_search.present?
        params[:query] = saved_search.query
        ids = matched_search_ids(params)
        UnreadEntry.where(user_id: @user.id, entry_id: ids).delete_all
      end
    elsif params[:type] == 'search'
      params[:query] = params[:data]
      ids = matched_search_ids(params)
      UnreadEntry.where(user_id: @user.id, entry_id: ids).delete_all
    end

    @mark_selected = true
    get_feeds_list

    respond_to do |format|
      format.js
    end
  end

  def preload
    @user = current_user
    ids = params[:ids].split(',').map {|i| i.to_i }
    @entries = Entry.where(id: ids).includes(:feed)
    @entries = update_with_state(@entries)

    # View inline setting
    view_inline_settings = {}
    subscriptions = Subscription.where(user: @user).pluck(:feed_id, :view_inline)
    subscriptions.each { |feed_id, setting| view_inline_settings[feed_id] = setting }

    tags = {}
    taggings = @user.taggings.pluck(:feed_id, :tag_id)
    taggings.each do |feed_id, tag_id|
      if tags[feed_id]
        tags[feed_id] << tag_id
      else
        tags[feed_id] = [tag_id]
      end
    end

    result = {}
    @entries.each do |entry|
      readability = (@user.sticky_view_inline == '1' && view_inline_settings[entry.feed_id] == true)
      locals = {
        entry: entry,
        services: sharing_services(entry),
        read: true, # will always be marked as read when viewing
        starred: entry.starred,
        content_view: false
      }
      result[entry.id] = {
        content: render_to_string(partial: "entries/show", formats: [:html], locals: locals),
        read: entry.read,
        starred: entry.starred,
        tags: tags[entry.feed_id] ? tags[entry.feed_id] : [],
        feed_id: entry.feed_id
      }
    end

    respond_to do |format|
      format.json { render json: result.to_json }
    end
  end

  def mark_as_read
    @user = current_user
    UnreadEntry.where(user: @user, entry_id: params[:id]).delete_all
    render nothing: true
  end

  def mark_direction_as_read
    @user = current_user
    ids = params[:ids].split(',').map {|i| i.to_i }
    if params[:direction] == 'above'
      UnreadEntry.where(user: @user, entry_id: ids).delete_all
    else
      if params[:type] == 'feed'
        UnreadEntry.where(user: @user, feed_id: params[:data]).where.not(entry_id: ids).delete_all
      elsif params[:type] == 'tag'
        feed_ids = @user.taggings.where(tag_id: params[:data]).pluck(:feed_id)
        UnreadEntry.where(user: @user, feed_id: feed_ids).where.not(entry_id: ids).delete_all
      elsif params[:type] == 'starred'
        starred = @user.starred_entries.pluck(:entry_id)
        UnreadEntry.where(user: @user, entry_id: starred).where.not(entry_id: ids).delete_all
      elsif  %w{unread all}.include?(params[:type])
        UnreadEntry.where(user: @user).where.not(entry_id: ids).delete_all
      elsif params[:type] == 'saved_search'
        saved_search = @user.saved_searches.where(id: params[:data]).first
        if saved_search.present?
          params[:query] = saved_search.query
          search_ids = matched_search_ids(params)
          ids = search_ids - ids
          UnreadEntry.where(user_id: @user.id, entry_id: ids).delete_all
        end
      elsif params[:type] == 'search'
        params[:query] = params[:data]
        search_ids = matched_search_ids(params)
        ids = search_ids - ids
        UnreadEntry.where(user_id: @user.id, entry_id: ids).delete_all
      end
    end

    @mark_selected = true
    get_feeds_list

    respond_to do |format|
      format.js
    end
  end

  def search
    @user = current_user
    @escaped_query = params[:query].gsub("\"", "'").html_safe if params[:query]

    @entries = Entry.search(params, @user)
    @entries = update_with_state(@entries)
    @page_query = @entries

    @append = !params[:page].nil?

    @type = 'all'
    @data = nil

    @search = true

    @collection_title = 'Search'
    @collection_favicon = 'favicon-search'

    @saved_search = SavedSearch.new

    respond_to do |format|
      format.js { render partial: 'shared/entries' }
    end
  end

  def push_view
    user_id = verify_push_token(params[:user])
    @user = User.find(user_id)
    @entry = Entry.find(params[:id])
    UnreadEntry.where(user: @user, entry: @entry).delete_all
    redirect_to @entry.fully_qualified_url, status: :found
  end

  private

  def sharing_services(entry)
    @user_sharing_services ||= @user.sharing_services
    services = []

    if @user_sharing_services.present?
      begin
        @user_sharing_services.each do |service|
          entry_url = entry.fully_qualified_url ? ERB::Util.url_encode(entry.fully_qualified_url) : ''
          title = entry.title ? ERB::Util.url_encode(entry.title) : ''
          feed_name = entry.feed.title ? ERB::Util.url_encode(entry.feed.title) : ''
          url = service.url.clone
          url = url.gsub('${url}', entry_url).gsub('${title}', title).gsub('${source}', feed_name)
          if url.start_with?('http')
            target = '_blank'
          else
            target = '_self'
          end
          services << {label: service.label, url: url, target: target}
        end
      rescue Exception => e
      end
    end
    services
  end

  def view_inline
    begin
      if @content_view
        url = @entry.fully_qualified_url
        @content = Rails.cache.fetch("content_view:#{Digest::SHA1.hexdigest(url)}") do
          result = ReadabilityParser.parse(url)
          result.content
        end
      else
        @content = @entry.content
      end
    rescue => e
      @content = '(no content)'
    end

  end

  def matched_search_ids(params)
    params[:load] = false
    query = params[:query]
    entries = Entry.search(params, @user)
    ids = entries.results.map {|entry| entry.id.to_i}
    if entries.total_pages > 1
      2.upto(entries.total_pages) do |page|
        params[:page] = page
        params[:query] = query
        entries = Entry.search(params, @user)
        ids = ids.concat(entries.results.map {|entry| entry.id.to_i})
      end
    end
    ids
  end

end
