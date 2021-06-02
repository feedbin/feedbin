class SavePage
  include Sidekiq::Worker
  sidekiq_options queue: :critical

  attr_reader :user, :url, :title

  def perform(user_id, url, title)
    @user = User.find(user_id)
    @url = url
    @title = title
    entry = create_webpage_entry
    ImageSaver.perform_async(entry.id)
    FaviconFetcher.perform_async(host, true)
    entry
  end

  def create_webpage_entry
    user.subscriptions.create_with(kind: Subscription.kinds[:generated]).find_or_create_by!(feed: pages_feed)
    pages_feed.entries.create_with(build_entry).find_or_create_by!(public_id: public_id)
  end

  def feed_url
    hash = Digest::SHA1.hexdigest(user.page_token + user.id.to_s)
    URI::HTTP.build(
      host: ENV["PAGES_DOMAIN"],
      path: "/#{hash}"
    ).to_s
  end

  def parsed_result
    @parsed_result ||= MercuryParser.parse(url)
  rescue
    nil
  end

  def host
    URI(url).host
  rescue
    url
  end

  def public_id
    Digest::SHA1.hexdigest(feed_url + url)
  end

  def pages_feed
    @pages_feed ||= user.feeds.pages.take || Feed.create_with(build_feed).find_or_create_by!(feed_url: feed_url)
  end

  def build_feed
    {
      title: "Pages",
      feed_url: feed_url,
      site_url: URI::HTTP.build(host: ENV["PAGES_DOMAIN"]).to_s,
      protected: true,
      host: ENV["PAGES_DOMAIN"],
      feed_type: :pages
    }
  end

  def build_entry
    {
      author: parsed_result&.author,
      content: parsed_result&.content,
      title: parsed_result&.title || title,
      url: url,
      published: parsed_result&.published || Time.now,
      public_id: public_id,
      skip_recent_post_check: true,
      data: TweetPage.tweet(url, user)
    }
  end
end
