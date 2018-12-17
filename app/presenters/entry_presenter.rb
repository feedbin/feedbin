class EntryPresenter < BasePresenter
  YOUTUBE_URLS = [
    %r(https?://youtu\.be/(.+)),
    %r(https?://www\.youtube\.com/watch\?v=(.*?)(&|#|$)),
    %r(https?://m\.youtube\.com/watch\?v=(.*?)(&|#|$)),
    %r(https?://www\.youtube\.com/embed/(.*?)(\?|$)),
    %r(https?://www\.youtube\.com/v/(.*?)(#|\?|$)),
    %r(https?://www\.youtube\.com/user/.*?#\w/\w/\w/\w/(.+)\b),
  ]

  INSTAGRAM_URLS = [
    %r(https?://www\.instagram\.com/p/(.*?)(/|#|\?|$)),
    %r(https?://instagram\.com/p/(.*?)(/|#|\?|$)),
  ]

  VIMEO_URLS = [
    %r(https?://vimeo\.com/video/(.*?)(#|\?|$)),
    %r(https?://vimeo\.com/([0-9]+)(#|\?|$)),
  ]

  presents :entry

  def entry_link(&block)
    options = {
      remote: true, class: "wrap", data: {
        behavior: "selectable open_item show_entry_content entry_info",
        mark_as_read_path: @template.mark_as_read_entry_path(entry),
        recently_read_path: @template.recently_read_entry_path(entry),
        entry_id: entry.id,
        entry_info: {id: entry.id, feed_id: entry.feed_id, published: entry.published.to_i},
      },
    }
    @template.link_to @template.entry_path(entry), options do
      yield
    end
  end

  def published_date
    if entry.tweet?
      entry.main_tweet.created_at.to_s(:full_human)
    else
      if entry.published
        entry.published.to_s(:full_human)
      else
        ""
      end
    end
  end

  def datetime
    if entry.tweet?
      entry.main_tweet.created_at.to_s(:datetime)
    else
      if entry.published
        entry.published.to_s(:datetime)
      else
        ""
      end
    end
  end

  def parsed_date(date, format)
    begin
      date = Time.parse(date)
      date.to_s(format)
    rescue Exception
      nil
    end
  end

  def content
    ContentFormatter.format!(formatted_content, entry)
  rescue => e
    Rails.logger.info { e.inspect }
    @template.content_tag(:p, "&ndash;&ndash;".html_safe)
  end

  def api_content
    ContentFormatter.api_format(formatted_content, entry)
  rescue => e
    Rails.logger.info { e.inspect }
    @template.content_tag(:p, "&ndash;&ndash;".html_safe)
  end

  def app_content
    ContentFormatter.app_format(formatted_content, entry)
  rescue => e
    Rails.logger.info { e.inspect }
    @template.content_tag(:p, "&ndash;&ndash;".html_safe)
  end

  def formatted_content
    @formatted_content ||= begin
      formatted_content = entry.content
      if text?
        formatted_content = ContentFormatter.text_email(formatted_content)
      elsif youtube?
        formatted_content = ContentFormatter.text_email(formatted_content)
        formatted_content = @template.content_tag(:iframe, "", width: entry.data["media_width"], height: entry.data["media_height"], src: "https://www.youtube-nocookie.com/embed/#{entry.data["youtube_video_id"]}?rel=0&amp;showinfo=0", frameborder: 0, allowfullscreen: true) + formatted_content
      end
      formatted_content
    end
  end

  def text?
    entry.content_format == "text"
  end

  def has_content?
    entry.summary.respond_to?(:length) && entry.summary.length > 0
  end

  def show_body?
    if entry.tweet?
      true
    else
      has_content? && sanitized_title.present?
    end
  end

  def title
    length = 100
    if entry.tweet?
      text = entry.tweet_summary.html_safe
      length = 280
    elsif sanitized_title.present?
      text = sanitized_title
    elsif !entry.summary.blank?
      text = entry.summary
      length = 240
    end

    if text.blank?
      text = "--".html_safe
    end
    @template.truncate(text, length: length, omission: "…", escape: false)
  end

  def retweet_text
    HTMLEntities.new.decode(entry.tweet_summary(entry.main_tweet.quoted_status))
  end

  def entry_view_title
    @entry_view_title ||= begin
      text = sanitized_title
      if text.blank?
        text = @template.content_tag(:span, entry.feed.title, data: {behavior: "user_title", feed_id: entry.feed_id}).html_safe
      end
      text
    end
  end

  def sanitized_title
    @sanitized_title ||= @template.raw(@template.strip_tags(entry.title))
  end

  def author
    if entry.author
      clean_author = @template.strip_tags(entry.author)
      clean_author = "by " + @template.content_tag(:span, clean_author, class: "author")
    else
      clean_author = ""
    end
    clean_author.html_safe
  end

  def media_size
    begin
      size = Integer(entry.data["enclosure_length"])
      size = @template.number_to_human_size(size)
      size = "(#{size})"
    rescue Exception
      size = ""
    end
  end

  def download_title
    "Download #{media_size}"
  end

  def media
    output = ""
    if has_enclosure? && media_type.present?
      if media_type == :video
        output += @template.video_tag enclosure_url, preload: "none"
      elsif media_type == :audio
        output += @template.audio_tag enclosure_url, preload: "none"
      end
      output += @template.link_to "Download #{media_size}", enclosure_url, class: "download-link"
    end
    output
  end

  def saved_page(url)
    if entry.data && entry.data["saved_pages"] && page = entry.data["saved_pages"][url]
      if page["result"]
        MercuryParser.new(nil, page)
      end
    end
  end

  def media_class
    classes = []
    if media_type == :audio
      classes.push("media")
    end

    if !title? || entry.tweet?
      classes.push("no-title")
    end

    if entry.retweet?
      classes.push("retweet")
    end

    classes.join(" ")
  end

  def media_type
    if entry.data && entry.data["enclosure_type"] == "video/mp4"
      :video
    elsif entry.data && ["audio/mp3", "audio/mpeg"].include?(entry.data["enclosure_type"])
      :audio
    else
      nil
    end
  end

  def media_duration
    if entry.data["itunes_duration"]
      entry.data["itunes_duration"]
    else
      ""
    end
  end

  def media_image
    entry.itunes_image
  end

  def extracted_articles
    articles = []
    if entry.data && entry.data["saved_pages"]
      entry.data["saved_pages"].each do |url, page|
        begin
          if page["result"]
            parsed = MercuryParser.new(nil, page)
            content = ContentFormatter.api_format(parsed.content, nil)
            data = {
              url: url,
              title: parsed.title,
              host: parsed.domain,
              author: parsed.author,
              content: content,
            }
            articles.push data
          end
        rescue
        end
      end
    end
    articles
  end

  def media_subtitle
    if entry.data && entry.data["itunes_subtitle"]
      subtitle = @template.strip_tags(entry.data["itunes_subtitle"])
      body = @template.strip_tags(entry.content)
      decoder = HTMLEntities.new
      body = decoder.decode(body)
      if !body.include?(subtitle)
        @template.content_tag :figcaption do
          @template.raw(subtitle)
        end
      end
    end
  end

  def feed_domain_matches?(comparison)
    begin
      uri = URI.parse(entry.feed.site_url)
      uri.host == comparison || uri.host == comparison.sub("www.", "")
    rescue Exception
      false
    end
  end

  def has_enclosure?
    entry.data.respond_to?(:[]) && entry.data["enclosure_url"].present?
  end

  def enclosure_url
    if has_enclosure?
      base = Addressable::URI.parse(entry.fully_qualified_url)
      base.join(entry.data["enclosure_url"]).to_s
    end
  end

  def has_media?
    !media_type.nil? || content.include?("<iframe")
  end

  def youtube?
    entry.data && entry.data["youtube_video_id"].present?
  end

  def image
    if entry.processed_image?
      padding = (entry.image["height"].to_f / entry.image["width"].to_f).round(4) * 100
      @template.content_tag :span, class: "entry-image" do
        @template.content_tag :span, "", data: {src: entry.processed_image}, style: "padding-top: #{padding}%;"
      end
    end
  end

  def entry_type
    if entry.data && entry.data["type"].present?
      entry.data["type"]
    else
      "default"
    end
  end

  def entry_type_class
    "entry-type-#{entry_type} entry-format-#{entry_type}-#{entry.content_format}"
  end

  def content_diff
    before = ContentFormatter.api_format(entry.original["content"], entry)
    HTMLDiff::Diff.new(before, entry.content).inline_html
  rescue
    nil
  end

  def decoder
    @decoder ||= HTMLEntities.new
  end

  def content_text
    @content_text ||= begin
      text = Sanitize.fragment(entry.content,
                               remove_contents: true,
                               elements: %w{html body div span
                                            h1 h2 h3 h4 h5 h6 p blockquote pre
                                            a abbr acronym address big cite code
                                            del dfn em ins kbd q s samp
                                            small strike strong sub sup tt var
                                            b u i center
                                            dl dt dd ol ul li
                                            fieldset form label legend
                                            table caption tbody tfoot thead tr th td
                                            article aside canvas details embed
                                            figure figcaption footer header hgroup
                                            menu nav output ruby section summary})
      text = ReverseMarkdown.convert(text)
      text = ActionController::Base.helpers.strip_tags(text)
      decoder.decode(text)
    end
  end

  def app_summary
    decoder.decode(@template.strip_tags(entry.summary))
  end

  def summary
    if !entry.tweet && title?
      summary = entry.summary.truncate(120, separator: " ", omission: "…")
      @template.content_tag(:p, summary, class: "body")
    end
  rescue
    nil
  end

  def trimmed_summary(text)
    output = ""
    parts = text.split(". ")
    a = parts.each_with_index do |part, index|
      new_part = part + ". "
      output << new_part
      if index == 0
        if output.length > 180
          output = output[0..180]
          output = output[0..-2]
          return output << "…"
        end
      else
        if output.length > 180
          return output.sub(new_part, "")
        end
      end
    end
    output
  end

  def app_title
    (entry.title.present?) ? decoder.decode(@template.strip_tags(entry.title.strip)) : nil
  end

  def app_author
    (entry.author.present?) ? decoder.decode(@template.strip_tags(entry.author.strip)) : nil
  end

  def has_diff?
    entry.content.present? && entry.original.present? && entry.original["content"].present? && entry.original["content"].length != entry.content.length
  end

  def is_updated_entry?
    @locals && @locals[:updated_entries].respond_to?(:include?) && @locals[:updated_entries].include?(entry.id)
  end

  def audio_duration
    if media_duration && parts = media_duration.split(":").map(&:to_i)
      if parts.length == 3
        hours, minutes, seconds = parts
        result = hours * 60 + minutes
        "#{result} minutes"
      end
    end
  rescue
    nil
  end

  def profile_image(feed)
    if entry.tweet?
      @template.content_tag :span, "", class: "favicon-wrap twitter-profile-image" do
        url = tweet_profile_image_uri(entry.main_tweet)
        fallback = @template.image_url("favicon-profile-default.png")
        @template.image_tag_with_fallback(fallback, url, alt: "")
      end
    elsif entry.micropost?
      @template.content_tag :span, "", class: "favicon-wrap twitter-profile-image" do
        fallback = @template.image_url("favicon-profile-default.png")
        url = @template.camo_link(entry.micropost.author_avatar)
        @template.image_tag_with_fallback(fallback, url, alt: "")
      end
    else
      favicon(feed)
    end
  end

  def feed_title
    if entry.tweet?
      @template.content_tag(:span, "", class: "title-inner") do
        "#{tweet_name(entry.main_tweet)} #{@template.content_tag(:span, tweet_screen_name(entry.main_tweet))}".html_safe
      end
    elsif entry.micropost?
      @template.content_tag(:span, "", class: "title-inner") do
        "#{entry.micropost.author_name} #{@template.content_tag(:span, entry.micropost.author_display_username)}".html_safe
      end
    elsif entry.title.blank? && entry.author.present?
      @template.content_tag(:span, "", class: "title-inner") do
        entry.author
      end
    else
      @template.content_tag(:span, "", class: "title-inner", data: {behavior: "user_title", feed_id: entry.feed.id}) do
        entry.feed.title
      end
    end
  end

  def title?
    entry.title.present?
  end

  def tweet_classes(tweet)
    classes = ["tweet-author-#{tweet.user.id}"]
    parent = (@locals[:parent]) ? @locals[:parent] : entry.main_tweet
    if @locals[:tweet_counter].present? && tweet.user.id == parent.user.id
      if tweet.in_reply_to_user_id? && tweet.in_reply_to_user_id != parent.user.id && tweet.id != parent.id
        classes.push("tweet-author-reply")
      end
    end

    if @locals[:tweet_counter] == 0
      classes.push("main-tweet")
      classes.push("main-tweet-conversation")
    else
      classes.push(@locals[:css])
    end
    classes.join(" ")
  end

  def tweet_in_reply_to(tweet)
    tweet = tweet ? tweet : entry.main_tweet
    if tweet.to_h[:display_text_range] && tweet.in_reply_to_status_id?
      range = tweet.to_h[:display_text_range]
      content_start = range.last
      mentions = tweet.user_mentions.select do |mention|
        mention.indices.last <= content_start
      end.map do |mention|
        @template.link_to "@#{mention.screen_name}", "https://twitter.com/#{mention.screen_name}", target: "_blank"
      end
      if !mentions.empty?
        @template.content_tag(:p, "", class: "tweet-mentions") do
          "Replying to #{mentions.join(", ")}".html_safe
        end
      end
    end
  end

  def tweet_name(tweet)
    tweet.user.name
  end

  def tweet_screen_name(tweet)
    "@" + tweet.user.screen_name
  end

  def tweet_user_url(tweet)
    "https://twitter.com/#{tweet.user.screen_name}"
  end

  def tweet_media
    all_tweets.each_with_object([]) do |tweet, array|
      tweet.media.each do |m|
        array.push(m)
      end
    end
  end

  def tweet_urls
    all_tweets.each_with_object([]) do |tweet, array|
      tweet.urls.each do |url|
        array.push(url)
      end
    end
  end

  def all_tweets
    Array.new.tap do |array|
      array.push(entry.main_tweet)
      array.push(entry.main_tweet.quoted_status) if entry.main_tweet.quoted_status?
    end
  end

  def tweet_retweeted_message
    "Retweeted by " + (entry.tweet.user.name || "@" + entry.tweet.user.screen_name)
  end

  def tweet_retweeted_image
    if entry.tweet.user.profile_image_uri? && entry.tweet.user.profile_image_uri_https("normal")
      @template.camo_link(entry.tweet.user.profile_image_uri_https("normal"))
    else
      @template.image_url("favicon-profile-default.png")
    end
  end

  # Sizes: normal, bigger
  def tweet_profile_image_uri(tweet, size = "bigger")
    if tweet.user.profile_image_uri? && tweet.user.profile_image_uri_https(size)
      @template.camo_link(tweet.user.profile_image_uri_https("bigger"))
    else
      @template.image_url("favicon-profile-default.png")
    end
  end

  def tweet_youtube_embed(url, tag = :iframe)
    url = url.expanded_url.to_s
    if YOUTUBE_URLS.find { |format| url =~ format } && $1
      youtube_id = $1
      iframe_embed("https://www.youtube.com/embed/#{youtube_id}", tag)
    else
      false
    end
  end

  def tweet_vimeo_embed(url, tag = :iframe)
    url = url.expanded_url.to_s
    if VIMEO_URLS.find { |format| url =~ format } && $1
      vimeo_id = $1
      iframe_embed("https://player.vimeo.com/video/#{vimeo_id}", tag)
    else
      false
    end
  end

  def iframe_embed(url, tag)
    if tag == :iframe
      @template.content_tag(:iframe, "", src: url, height: 9, width: 16, frameborder: 0, allowfullscreen: true).html_safe
    else
      context = {
        embed_url: Rails.application.routes.url_helpers.iframe_embeds_path,
        embed_classes: "iframe-placeholder entry-callout system-content",
      }
      filter = HTML::Pipeline::IframeFilter.new("", context)
      attributes = filter.iframe_attributes(url, 16, 9)
      @template.content_tag(:div, "", attributes).html_safe
    end
  end

  def tweet_instagram_embed(url)
    url = url.expanded_url.to_s
    if INSTAGRAM_URLS.find { |format| url =~ format } && $1
      instagram_id = $1
      @template.link_to url, target: "_blank" do
        @template.image_tag(@template.camo_link("https://instagram.com/p/#{instagram_id}/media/?size=l"), class: "responsive")
      end
    else
      false
    end
  end

  def tweet_location(tweet)
    (tweet.place?) ? tweet.place.full_name : nil
  end

  def tweet_video?(media)
    media.type == "video" || media.type == "animated_gif"
  end

  def tweet_video(media)
    options = {
      poster: media.media_url_https.to_s + ":large",
      width: media.video_info.aspect_ratio.first,
      height: media.video_info.aspect_ratio.last,
    }

    if media.type == "animated_gif"
      options["autoplay"] = false
      options["loop"] = true
    end

    highest_quality_video = media.video_info.variants.max_by do |element|
      if element.content_type == "video/mp4" && element.bitrate
        element.bitrate
      else
        0
      end
    end

    @template.video_tag highest_quality_video.url.to_s, options
  end

  def tweet_text(tweet, tag = true)
    text = entry.tweet_text(tweet)
    if text.present?
      if tag
        @template.content_tag(:p, class: "tweet-text") do
          text.html_safe
        end
      else
        text.html_safe
      end
    end
  end

  def quoted_status?
    entry.main_tweet.quoted_status?
  end

  def quoted_status
    entry.main_tweet.quoted_status
  end
end
