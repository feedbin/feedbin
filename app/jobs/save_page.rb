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

  attr_reader :user, :url, :title

  def perform(user_id, url, title)
    @user = User.find(user_id)
    @url = url
    @title = title
    entry = create_webpage_entry

    ImageSaver.perform_async(entry.id)
    IconCrawler::Provider::Favicon.perform_async(host, true)
    
    if parsed_result.nil?
      raise MissingPage.new("Missing page, retrying", entry)
    end

    if match = IframeEmbed::Youtube.recognize_url?(url)
      embed = Embed.where(provider_id: match[1]).take
      unless embed.present?
        HarvestEmbeds.new.perform(entry.id, true)
        embed = Embed.where(provider_id: match[1]).take
      end
      if embed.present?
        entry.update(content: embed.data.safe_dig("snippet", "description"), title: embed.data.safe_dig("snippet", "title"), author: embed.data.safe_dig("snippet", "channelTitle"))
      end
    end

    entry
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
      MercuryParser.parse(url)
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
