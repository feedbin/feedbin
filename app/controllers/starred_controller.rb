class StarredController < ApplicationController
  skip_before_action :authorize

  def index
    @user = User.find_by_starred_token(params[:starred_token])

    if @user && @user.starred_feed_enabled == '1'
      @title = "Feedbin Starred Entries for #{@user.email}"
      @starred_entries = @user.starred_entries.order('created_at DESC').limit(50)
      entry_ids = @starred_entries.map {|starred_entry| starred_entry.entry_id}
      @entries = Entry.where(id: entry_ids).includes(:feed).map { |entry|
        entry.content = ContentFormatter.absolute_source(entry.content, entry)
        entry.summary = ContentFormatter.absolute_source(entry.summary, entry)
        entry
      }
      @entries = @entries.sort_by {|entry| entry_ids.index(entry.id) }
    else
      render_404
    end
  end
end
