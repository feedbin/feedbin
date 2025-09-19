class SavePage
  class MissingPage < StandardError
    attr_reader :entry
    def initialize(message, entry)
      @entry = entry
      super(message)
    end
  end

  include Sidekiq::Worker
  sidekiq_options queue: :default_critical

  attr_reader :user, :url, :title, :path

  def perform(user_id, url, title, path = nil)
    @user = User.find(user_id)
    @url = url
    @title = title
    @path = path

    embed = find_embed
    entry = create_webpage_entry
    if embed.present?
      entry.update(
        content: embed.data.safe_dig("snippet", "description"),
        title: embed.data.safe_dig("snippet", "title"),
        author: embed.data.safe_dig("snippet", "channelTitle"),
        embed_duration: embed.duration_in_seconds
      )
    end

    ImageSaver.perform_async(entry.id)
    FaviconCrawler::Finder.perform_async(host)

    if parsed_result.nil?
      raise MissingPage.new("Missing page, retrying", entry)
    end

    entry
  end

  def find_embed
    match = IframeEmbed::Youtube.recognize_url?(url)
    return if match.blank?
    embed = Embed.youtube_video.where(provider_id: match[1]).take
    if embed.blank?
      HarvestEmbeds.new.add_missing_to_queue([match[1]])
      HarvestEmbeds.new.perform(nil, true)
      embed = Embed.youtube_video.where(provider_id: match[1]).take
    end
    embed
  rescue
    nil
  end

  def create_webpage_entry
    user.subscriptions.create_with(kind: Subscription.kinds[:generated]).find_or_create_by!(feed: pages_feed)
    entry = pages_feed.entries.create_with(build_entry).find_or_create_by!(public_id: public_id)
    entry.update(build_entry)
    entry
  end

  def feed_url
    hash = Digest::SHA1.hexdigest(user.page_token + user.id.to_s)
    URI::HTTP.build(
      host: ENV["PAGES_DOMAIN"],
      path: "/#{hash}"
    ).to_s
  end

  def parsed_result
    return @parsed_result if defined?(@parsed_result)

    @parsed_result = begin
      if path
        MercuryParser.parse(url, html: File.read(path))
      else
        MercuryParser.parse(url)
      end
    rescue
      nil
    end
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
    data = TweetPage.tweet(url, user) || {}
    if match = IframeEmbed::Youtube.recognize_url?(url)
      data[:youtube_video_id] = match[1]
    end
    {
      author: parsed_result&.author,
      content: parsed_result&.content,
      title: parsed_result&.title || title&.sub("Sending to Feedbin: ", "")&.strip,
      url: url,
      published: parsed_result&.published || Time.now,
      public_id: public_id,
      skip_recent_post_check: true,
      data: data
    }
  end
end
