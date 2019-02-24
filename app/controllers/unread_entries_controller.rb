class UnreadEntriesController < ApplicationController
  def update
    @user = current_user
    @entry = Entry.find(params[:id])
    unread_entry = UnreadEntry.where(user: @user, entry: @entry)

    if unread_entry.present?
      unread_entry.delete_all
    else
      UnreadEntry.create_from_owners(@user, @entry)
    end

    head :ok
  end
end
