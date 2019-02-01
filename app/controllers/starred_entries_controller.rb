class StarredEntriesController < ApplicationController
  skip_before_action :authorize, only: :index

  def index
    @user = User.find_by_starred_token(params[:starred_token])

    if @user&.setting_on?(:starred_feed_enabled)
      @title = "Feedbin Starred Entries for #{@user.email}"
      @entries = Rails.cache.fetch("#{@user.id}:starred_feed") {
        @starred_entries = @user.starred_entries.order("created_at DESC").limit(50)
        entry_ids = @starred_entries.map { |starred_entry| starred_entry.entry_id }
        @entries = Entry.where(id: entry_ids).includes(:feed).map { |entry|
          entry.content = ContentFormatter.absolute_source(entry.content, entry)
          entry.summary = ContentFormatter.absolute_source(entry.summary, entry)
          entry
        }
        @entries.sort_by { |entry| entry_ids.index(entry.id) }
      }
    else
      render_404
    end
  end

  def export
    user = current_user
    StarredEntriesExport.perform_async(user.id)
    redirect_to settings_import_export_url, notice: "Starred export has begun. You will receive an email with the download link shortly."
  end

  def update
    @user = current_user
    @entry = Entry.find(params[:id])
    starred_entry = StarredEntry.where(user: @user, entry: @entry)

    if starred_entry.present?
      starred_entry.destroy_all
    else
      StarredEntry.create_from_owners(@user, @entry, "web")
    end

    head :ok
  end
end
