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
        micropost: Micropost.new(item),
        fully_qualified_url: item["url"],
        published: parse_published(item["date_published"]),
        content: item["content_html"],
        id: item["id"],
        media: []
      }
      OpenStruct.new(data)
    end
  end

  # date_published is an optional item field in both JSON Feed v1 and v1.1, so a
  # conformant reply can omit it -- and Time.parse turns that, or anything Ruby
  # cannot read, into an exception that fails the whole conversation rather than
  # the one reply. The template renders a reply with no timestamp without one.
  def parse_published(value)
    Time.parse(value.to_s)
  rescue ArgumentError
    nil
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
