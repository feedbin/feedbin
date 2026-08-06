class MicropostsController < ApplicationController
  def thread
    @user = current_user
    @entry = authorized_entry or return
    @microposts = Rails.cache.fetch("microblog_thread:#{@entry.id}", expires_in: 2.minutes) {
      build_microposts
    }
  end

  private

  def build_microposts
    replies = get_replies
    items = replies["items"] || []
    # Item-level authors are optional in JSON Feed, and Micropost#valid? already
    # decides whether a post can be rendered -- Entry#micropost asks. Building
    # these without asking meant one authorless reply raised out of the template
    # and took the whole conversation with it.
    items.reverse.filter_map do |item|
      micropost = Micropost.new(item)
      next unless micropost.valid?

      OpenStruct.new({
        micropost: micropost,
        fully_qualified_url: item["url"],
        published: parse_published(item["date_published"]),
        content: item["content_html"],
        id: item["id"],
        media: []
      })
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
    # The http gem's default is no deadline at all, so a micro.blog that
    # accepts the connection and stops talking holds this Puma thread until the
    # far end closes the socket. Every other outbound call here sets one.
    HTTP.timeout(write: 5, connect: 5, read: 5)
      .auth(auth)
      .get("https://micro.blog/posts/conversation", params: {id: thread_id})
      .parse
  end

  def thread_id
    @entry.entry_id
  end
end
