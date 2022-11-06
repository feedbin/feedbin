class SearchDataV2
  def initialize(entry)
    @entry = entry
  end

  def to_h
    {}.tap do |hash|
      hash[:id]             = @entry.id
      hash[:feed_id]        = @entry.feed_id
      hash[:title]          = title
      hash[:url]            = @entry.fully_qualified_url
      hash[:author]         = @entry.author
      hash[:content]        = text
      hash[:published]      = @entry.published.iso8601
      hash[:updated]        = @entry.updated_at.iso8601
      hash[:link]           = links
      hash[:type]           = type
      hash[:media_duration] = nil
      hash[:word_count]     = hash[:content].split.length

      if @entry.tweet?
        hash[:twitter_screen_name] = "#{@entry.main_tweet.user.screen_name} @#{@entry.main_tweet.user.screen_name}"
        hash[:twitter_name]        = @entry.main_tweet.user.name
        hash[:twitter_retweet]     = @entry.tweet.retweeted_status?
        hash[:twitter_quoted]      = @entry.tweet.quoted_status?
        hash[:twitter_media]       = @entry.twitter_media?
        hash[:twitter_image]       = twitter_image
        hash[:twitter_link]        = twitter_link
      end
    end
  end

  def type
    if @entry.tweet?
      "tweet"
    elsif @entry.newsletter?
      "newsletter"
    elsif @entry.youtube?
      "youtube"
    elsif @entry.podcast?
      "podcast"
    else
      "feed"
    end
  end

  def document
    @document ||= Loofah.fragment(@entry.content).scrub!(:prune)
  end

  def emoji(content)
    content.respond_to?(:scan) ? content.scan(Unicode::Emoji::REGEX).join(" ") : nil
  end

  def text
    content = document.to_text(encode_special_chars: false).gsub(/\s+/, " ").squish
    content = nil if content.empty?
    content
  end

  def tweets
    @tweets ||= begin
      [].tap do |array|
        array.push(@entry.main_tweet)
        array.push(@entry.main_tweet.quoted_status) if @entry.main_tweet.quoted_status?
      end
    end
  end

  def twitter_image
    !!(tweets.find { |tweet| tweet.media? rescue nil })
  end

  def twitter_link
    !!(tweets.find { |tweet| tweet.urls? })
  end

  def title
    content = ContentFormatter.summary(@entry.title)
    content = nil if content.empty?
    content
  end

  def links
    links = [@entry.fully_qualified_url]
    document.css("a").each do |link|
      links.push(link["href"])
    end

    hosts = links.each_with_object([]) do |link, array|
      host = Addressable::URI.parse(link)&.host rescue nil
      next if host.nil?
      parts = host.split(".")
      next if parts.length < 2
      root = parts.last(2).join(".")
      array.push(root)
      array.push(host)
    end.uniq
  end
end
