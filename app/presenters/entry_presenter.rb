class EntryPresenter < BasePresenter
  YOUTUBE_URLS = [
    %r{https?://youtu\.be/(.+)},
    %r{https?://www\.youtube\.com/watch\?v=(.*?)(&|#|$)},
    %r{https?://m\.youtube\.com/watch\?v=(.*?)(&|#|$)},
    %r{https?://www\.youtube\.com/embed/(.*?)(\?|$)},
    %r{https?://www\.youtube\.com/v/(.*?)(#|\?|$)},
    %r{https?://www\.youtube\.com/user/.*?#\w/\w/\w/\w/(.+)\b}
  ]

  INSTAGRAM_URLS = [
    %r{https?://www\.instagram\.com/p/(.*?)(/|#|\?|$)},
    %r{https?://instagram\.com/p/(.*?)(/|#|\?|$)}
  ]

  VIMEO_URLS = [
    %r{https?://vimeo\.com/video/(.*?)(#|\?|$)},
    %r{https?://vimeo\.com/([0-9]+)(#|\?|$)}
  ]

  presents :entry

  def entry_summary(&block)
    options = {
      class: entry_summary_class,
      data: {entry_id: entry.id}
    }
    options[:dir] = "rtl" if @template.rtl?(entry.summary)
    @template.content_tag :li, options do
      yield
    end
  end

  def entry_link(&block)
    options = {
      class: "entry-summary-link",
      data: {
        behavior: "selectable open_item show_entry_content entry_info",
        remote: true,
        entry_info: {id: entry.id, feed_id: entry.feed_id, published: entry.published.to_i}.to_json,
        mark_as_read_path: @template.mark_as_read_entry_path(entry),
        recently_read_path: @template.recently_read_entry_path(entry),
        url: entry.fully_qualified_url
      }
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
    date = Time.parse(date)
    date.to_s(format)
  rescue Exception
    nil
  end

  def content
    ContentFormatter.format!(formatted_content, entry)
  rescue => e
    Rails.logger.info { e.inspect }
    @template.content_tag(:p, "&ndash;&ndash;".html_safe)
  end

  def is_numeric?(string)
    string = string.strip
    begin
      string.to_i.to_s == string
    rescue
      false
    end
  end

  def update_media_queries(html)
    regex = /@media(.*?)\(max-width:(.*?)px\)(.*?){/
    html.gsub(regex) do |string|
      matches = string.match(regex)
      if matches[2] && is_numeric?(matches[2])
        number = matches[2].to_i
        if number >= 400
          number = 10_000
        end
        string = "@media#{matches[1]}(max-width:#{number}px)#{matches[3]}{"
      end
      string
    end
  rescue
    html
  end

  def newsletter_content
    output = update_media_queries(formatted_content)
    output = ContentFormatter.newsletter_format(output)
    output = <<-eod
    <style>
    body {
      margin: 0  !important;
      padding: 0 !important;
    }
    table, td, img {
      max-width: 620px !important;
    }
    img[width="1"], img[height="1"] {
      display: none !important;
    }
    </style>
    #{output}
    eod
    output.html_safe
  rescue => e
    Rails.logger.info { e.inspect }
    @template.content_tag(:p, "&ndash;&ndash;".html_safe)
  end

  def newsletter_from?
    newsletter_from
  end

  def newsletter_from
    from = entry.newsletter_from || entry.data && entry.data.dig("newsletter", "data", "from")
    name, address = from.split(/[<>]/).map(&:strip)
    OpenStruct.new(name: name.delete('"'), address: address)
  rescue
    nil
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
      if text?
        ContentFormatter.text_email(entry.content)
      elsif youtube?
        @template.capture do
          @template.concat @template.content_tag(:iframe, "", width: entry.data["media_width"], height: entry.data["media_height"], src: "https://www.youtube-nocookie.com/embed/#{entry.data["youtube_video_id"]}?rel=0&amp;showinfo=0", frameborder: 0, allowfullscreen: true)
          @template.concat ContentFormatter.text_email(entry.content)
        end
      else
        entry.content
      end
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
    elsif entry.data&.dig("json_feed", "authors").respond_to?(:map)
      authors = entry.data.dig("json_feed", "authors").map {|a| @template.strip_tags(a["name"]) }
      if authors.length > 1
        authors[-1] = "and #{authors[-1]}"
      end
      clean_author = authors.join(", ")
    else
      clean_author = ""
    end

    if clean_author.present?
      clean_author = "by " + @template.content_tag(:span, clean_author, class: "author")
    end
    clean_author.html_safe
  end

  def media_size
    size = Integer(entry.data["enclosure_length"])
    size = @template.number_to_human_size(size)
    size = "(#{size})"
  rescue Exception
    size = ""
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

  def entry_summary_class
    classes = ["entry-summary", "feed-id-#{entry.feed_id}"]

    if media_type == :audio
      classes.push("media")
    end

    if entry.tweet? || entry.micropost?
      classes.push("no-title")
    end

    if entry.retweet?
      classes.push("re-tweet")
    end

    classes.join(" ")
  end

  def media_type
    if entry.data && entry.data["enclosure_type"] == "video/mp4"
      :video
    elsif entry.data && ["audio/mp3", "audio/mpeg"].include?(entry.data["enclosure_type"])
      :audio
    end
  end

  def media_duration
    entry.data["itunes_duration"] || ""
  end

  def media_image
    entry.itunes_image
  end

  def extracted_articles
    articles = []
    if entry.data && entry.data["saved_pages"]
      entry.data["saved_pages"].each do |url, page|
        if page["result"]
          parsed = MercuryParser.new(nil, page)
          content = ContentFormatter.api_format(parsed.content, nil)
          data = {
            url: url,
            title: parsed.title,
            host: parsed.domain,
            author: parsed.author,
            content: content
          }
          articles.push data
        end
      rescue
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
      unless body.include?(subtitle)
        @template.content_tag :figcaption do
          @template.raw(subtitle)
        end
      end
    end
  end

  def feed_domain_matches?(comparison)
    uri = URI.parse(entry.feed.site_url)
    uri.host == comparison || uri.host == comparison.sub("www.", "")
  rescue Exception
    false
  end

  def has_enclosure?
    entry.data.respond_to?(:[]) && entry.data["enclosure_url"].present?
  end

  def enclosure_url
    if has_enclosure?
      base = Addressable::URI.parse(entry.fully_qualified_url)
      base.join(entry.data["enclosure_url"]).to_s
    end
  rescue
    nil
  end

  def has_media?
    !media_type.nil? || content.include?("<iframe")
  end

  def youtube?
    entry.data && entry.data["youtube_video_id"].present?
  end

  def attached_image
    if entry.processed_image?
      image(entry.processed_image)
    end
  end

  def image(src)
    @template.content_tag :span, class: "entry-image" do
      @template.content_tag :span, "", data: {src: src}
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

  def decoder
    @decoder ||= HTMLEntities.new
  end

  def content_text
    @content_text ||= begin
      text = Sanitize.fragment(entry.content,
        remove_contents: true,
        elements: %w[html body div span
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
          menu nav output ruby section summary])
      text = ReverseMarkdown.convert(text)
      text = ActionController::Base.helpers.strip_tags(text)
      decoder.decode(text)
    end
  end

  def app_summary
    decoder.decode(@template.strip_tags(entry.summary))
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
    entry.title.present? ? decoder.decode(@template.strip_tags(entry.title.strip)) : nil
  end

  def app_author
    entry.author.present? ? decoder.decode(@template.strip_tags(entry.author.strip)) : nil
  end

  def has_diff?
    entry.content_diff.present?
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

  def profile_image
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
      favicon(entry.feed, entry)
    end
  end

  def summary
    if entry.tweet?
      text = entry.tweet_summary(nil, true).html_safe
      summary = @template.truncate(text, length: 280, omission: "", escape: false)
      @template.content_tag(:div, class: "summary light") do
        @template.content_tag(:span, summary)
      end
    elsif entry.micropost?
      summary = entry.summary.truncate(250, separator: " ", omission: "…")
      @template.content_tag(:div, class: "summary light") do
        @template.content_tag(:span, summary)
      end
    elsif title?
      summary = entry.summary.truncate(250, separator: " ", omission: "…")
      @template.content_tag(:div, class: "summary light") do
        @template.concat @template.content_tag(:span, title_text, class: "inline-title")
        @template.concat @template.content_tag(:span, summary, class: "summary-inner")
      end
    else
      @template.content_tag(:div, class: "summary light") do
        @template.concat @template.content_tag(:span, title, class: "inline-title")
      end
    end
  rescue
    nil
  end

  def title
    length = 240
    if entry.tweet?
      @template.content_tag(:span, "", class: "title-inner") do
        "#{tweet_name(entry.main_tweet)} #{@template.content_tag(:span, tweet_screen_name(entry.main_tweet), class: "light")}".html_safe
      end
    elsif entry.micropost?
      @template.content_tag(:span, "", class: "title-inner") do
        "#{entry.micropost.author_name} #{@template.content_tag(:span, entry.micropost.author_display_username, class: "light")}".html_safe
      end
    else
      if sanitized_title.present?
        text = sanitized_title
      elsif !entry.summary.blank?
        text = entry.summary
      end
      if text.blank?
        text = "--".html_safe
      end
      @template.truncate(text, length: length, omission: "…", escape: false)
    end
  end

  def title_text
    sanitized_title || "--".html_safe
  end

  def feed_title
    if entry.tweet? || entry.micropost?
      ""
    elsif entry.feed.pages?
      @template.content_tag(:div, class: "feed-title") do
        @template.content_tag(:span, "", class: "title-inner") do
          entry.hostname
        end
      end
    elsif entry.title.blank? && entry.author.present?
      @template.content_tag(:div, class: "feed-title") do
        @template.content_tag(:span, "", class: "title-inner") do
          entry.author
        end
      end
    else
      @template.content_tag(:div, class: "feed-title") do
        @template.content_tag(:span, "", class: "title-inner", data: {behavior: "user_title", feed_id: entry.feed.id}) do
          entry.feed.title
        end
      end
    end
  end

  def entry_header_title
    if entry.feed.pages?
      @template.content_tag(:span, "", class: "entry-feed-title") do
        entry.hostname
      end
    else
      @template.content_tag(:span, "", class: "entry-feed-title", data: {behavior: "user_title", feed_id: entry.feed.id}) do
        @template.strip_tags(entry.feed.title)
      end
    end
  end

  def title?
    entry.title.present?
  end

  def tweet_classes(tweet)
    classes = ["tweet-author-#{tweet.user.id}"]
    parent = @locals[:parent] || entry.main_tweet
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
    tweet ||= entry.main_tweet
    if tweet.to_h[:display_text_range] && tweet.in_reply_to_status_id?
      range = tweet.to_h[:display_text_range]
      content_start = range.last
      mentions = tweet.user_mentions.select { |mention|
        mention.indices.last <= content_start
      }.map { |mention|
        @template.link_to "@#{mention.screen_name}", "https://twitter.com/#{mention.screen_name}", target: "_blank"
      }
      unless mentions.empty?
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
    [].tap do |array|
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

  def tweet_profile_banner(tweet)
    @template.content_tag(:div, class: "profile-banner", data: { color_hash_seed: tweet.user.screen_name }) do
      if tweet.user.profile_banner_url?
        @template.image_tag(@template.camo_link(tweet.user.profile_banner_url_https("1500x500")))
      end
    end
  end

  # Sizes: normal, bigger
  def tweet_profile_image_uri(tweet, size = :bigger)
    if tweet.user.profile_image_uri? && tweet.user.profile_image_uri_https(size)
      @template.camo_link(tweet.user.profile_image_uri_https(size))
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
        embed_classes: "iframe-placeholder entry-callout system-content"
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
      @template.content_tag :div, data: {behavior: "entry_content_wrap"} do
        @template.content_tag :blockquote, class: "instagram-media", data: {instgrm_permalink: "https://instagram.com/p/#{instagram_id}/"} do
          @template.link_to url, target: "_blank" do
            @template.image_tag(@template.camo_link("https://instagram.com/p/#{instagram_id}/media/?size=l"), class: "responsive")
          end
        end
      end
    else
      false
    end
  end

  def tweet_location(tweet)
    tweet.place? ? tweet.place.full_name : nil
  end

  def tweet_video?(media)
    media.type == "video" || media.type == "animated_gif"
  end

  def tweet_video(media)
    options = {
      poster: @template.camo_link(media.media_url_https.to_s + ":large"),
      width: media.video_info.aspect_ratio.first,
      height: media.video_info.aspect_ratio.last,
      preload: "none"
    }

    if media.type == "animated_gif"
      options["autoplay"] = false
      options["loop"] = true
    end

    highest_quality_video = media.video_info.variants.max_by { |element|
      if element.content_type == "video/mp4" && element.bitrate
        element.bitrate
      else
        0
      end
    }

    @template.video_tag highest_quality_video.url.to_s, options
  end

  def tweet_text(tweet, tag = true, options = {})
    text = entry.tweet_text(tweet, options)
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

  def tweet_author_description(tweet)
    entities = tweet.to_h.dig(:user, :entities, :description)
    @template.content_tag(:p, class: "tweet-text") do
      if entities
        Twitter::TwitterText::Autolink.auto_link_usernames_or_lists(Twitter::TwitterText::Autolink.auto_link_with_json(tweet.user.description, entities)).html_safe
      else
        Twitter::TwitterText::Autolink.auto_link(tweet.user.description).html_safe
      end
    end
  end

  def tweet_author_verified?(tweet)
    tweet.user.verified?
  end

  def tweet_author_joined(tweet)
    "#{tweet.user.created_at.strftime("%b")} #{tweet.user.created_at.year}"
  end

  def tweet_author_joined_day(tweet)
    tweet.user.created_at.mday.to_s.chars.map(&:to_i)
  end

  def tweet_author_joined_datetime(tweet)
    tweet.user.created_at.iso8601
  end

  def tweet_author_location(tweet)
    tweet.user.location? ? tweet.user.location : nil
  end

  def tweet_author_location?(tweet)
    tweet.user.location?
  end

  def quoted_status?
    entry.main_tweet.quoted_status?
  end

  def quoted_status
    entry.main_tweet.quoted_status
  end

  def tweet_link_title
    saved_page(entry.main_tweet.urls.first.expanded_url.to_s)&.title
  end

  def tweet_link_host
    saved_page(entry.main_tweet.urls.first.expanded_url.to_s)&.domain
  end

  def quoted_tweet
    return unless quoted_tweet?
    @template.content_tag :div, class: "quoted-tweet light" do
      @template.concat @template.content_tag(:strong) { tweet_name(entry.main_tweet.quoted_status) }
      @template.concat " – "
      @template.concat retweet_text
    end
  end

  def quoted_tweet?
    entry.tweet? && entry.main_tweet.quoted_status?
  end

  def feed_wrapper(subscriptions, &block)
    if entry.feed.pages?
      @template.content_tag :span, class: "feed-button" do
        yield
      end
    elsif subscriptions.include?(entry.feed.id)
      @template.link_to @template.edit_subscription_path(entry.feed, app: true), remote: true, class: "feed-button link", title: "Edit feed", data: {behavior: "open_settings_modal", toggle: "tooltip"} do
        yield
      end
    else
      @template.content_tag :span, class: "feed-button" do
        yield
      end
    end
  end
end
