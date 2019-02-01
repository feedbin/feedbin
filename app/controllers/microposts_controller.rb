class MicropostsController < ApplicationController
  def thread
    @user = current_user
    @entry = Entry.find(params[:id])
    @microposts = Rails.cache.fetch("microblog_thread:#{@entry.id}", expires_in: 2.minutes) {
      build_microposts
    }
  end

  private

  def build_microposts
    replies = get_replies
    items = replies["items"] || []
    items.reverse.map do |item|
      data = {
        micropost: Micropost.new(item, nil),
        fully_qualified_url: item["url"],
        published: Time.parse(item["date_published"]),
        content: item["content_html"],
        id: item["id"],
      }
      OpenStruct.new(data)
    end
  end

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
