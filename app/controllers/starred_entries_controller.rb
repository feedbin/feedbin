class StarredEntriesController < ApplicationController

  def update
    @user = current_user
    @entry = Entry.find(params[:id])
    starred_entry = StarredEntry.where(user: @user, entry: @entry)

    if params[:starred] == 'true'
      @starred = true
      unless starred_entry.present?
        StarredEntry.create_from_owners(@user, @entry)
      end
    elsif params[:starred] == 'false'
      @starred = false
      starred_entry.destroy_all
    end

    respond_to do |format|
      format.js
    end
  end

end
