class MicropostsController < ApplicationController

  def thread
    @user = current_user
    @entry = Entry.find(params[:id])
    @replies = get_replies
  end

  private

  def get_replies
    auth = "Token #{ENV["MICROBLOG_TOKEN"]}"
    HTTP.auth(auth).get("https://micro.blog/posts/conversation", params: {id: thread_id}).parse
  end

  def thread_id
    @entry.entry_id
  end

  def authorize
    super && current_user.can_read_entry?(params[:id])
  end


end
