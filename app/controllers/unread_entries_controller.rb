class UnreadEntriesController < ApplicationController

  def update
    @user = current_user
    @entry = Entry.find(params[:id])
    unread_entry = UnreadEntry.where(user: @user, entry: @entry)

    if params[:read] == 'true'
      @read = true
      unread_entry.destroy_all
    elsif params[:read] == 'false'
      @read = false
      unless unread_entry.present?
        UnreadEntry.create_from_owners(@user, @entry)
      end
    end

    @tags = @user.tags.where(taggings: {feed_id: @entry.feed_id}).uniq.collect(&:id)
    respond_to do |format|
      format.js
    end
  end

end
