class FaviconComponent < ApplicationComponent

  def initialize(feed:, entry: nil, favicons: nil)
    @feed = feed
    @entry = entry
    @favicons = favicons
  end

  def view_template(&)
    if @feed.newsletter?
      icon_newsletter
    elsif @feed.twitter_user?
      icon_twitter_user
    elsif (channel_icon_url = entry_channel_icon_url)
      icon_entry_channel(channel_icon_url)
    elsif (icon_url = @feed.icon_url)
      icon_feed(icon_url)
    elsif @feed.pages? && @entry
      icon_pages
    elsif @feed.pages?
      icon_pages_default
    elsif (favicon_url = @feed.site_favicon&.public_url)
      icon_favicon(favicon_url, @feed.host)
    else
      icon_generated
    end
  end

  def icon_newsletter
    span class: "favicon-wrap collection-favicon" do
      Icon("favicon-newsletter")
    end
  end

  def icon_twitter_user
    span class: "favicon-wrap twitter-profile-image" do
      image_tag_with_fallback(
        image_url("favicon-profile-default.png"),
        RemoteFile.signed_url(@feed.twitter_user.profile_image_uri_https(:original)),
        alt: ""
      )
    end
  end

  # The avatar of this video's own channel, for entries whose channel is
  # not the feed's -- a playlist feed mixes videos from many channels. When
  # they match, the feed's resolution wins (its own icon row outranks the
  # shared channel avatar).
  def entry_channel_icon_url
    return nil if @entry.nil? || @entry.provider_parent_id.blank?
    return nil if @entry.provider_parent_id == @feed.channel_id
    Image.unified_url(@entry.channel_image_record&.storage_path)
  end

  # Always round: an embed_icon row is a YouTube channel avatar.
  def icon_entry_channel(url)
    span class: "favicon-wrap twitter-profile-image icon-format-round" do
      image_tag_with_fallback(
        image_url("favicon-profile-default.png"),
        url,
        alt: ""
      )
    end
  end

  # Takes the url rather than re-asking the feed: the legacy fallback inside
  # Feed#icon_url signs the url (an HMAC) on every call.
  def icon_feed(icon_url)
    span class: "favicon-wrap twitter-profile-image icon-format-#{@feed.custom_icon_format || @feed.default_icon_format}" do
      image_tag_with_fallback(
        image_url("favicon-profile-default.png"),
        icon_url,
        alt: ""
      )
    end
  end

  # A Pages entry keys on its own host, lower-cased, not the feed's.
  def icon_pages
    host = @entry.hostname&.downcase
    favicon_url = pages_favicon(host)&.public_url
    if favicon_url
      icon_favicon(favicon_url, host)
    else
      icon_pages_default
    end
  end

  # favicons is the collection-wide map the entry list resolves up front. Fall
  # back to a lookup for the callers that render one entry on its own.
  #
  # host is nullable, so an entry whose url will not parse would otherwise
  # query provider_id IS NULL and bind to an unrelated row.
  def pages_favicon(host)
    return nil if host.blank?
    return @favicons[host] if @favicons
    Image.provider_website_favicon.find_by(provider_id: host)
  end

  def icon_pages_default
    span class: "favicon-wrap collection-favicon" do
      Icon("favicon-saved")
    end
  end

  # The host comes from the feed or the entry, never from the record: an
  # images row is keyed by host in provider_id, and the class must not care
  # which record it got.
  def icon_favicon(url, host)
    span class: "favicon-wrap" do
      span class: "favicon #{host_class(host)}", style: "background-image: url(#{url});"
    end
  end

  # application.scss keys on .host-feedbin-com and .host-twitter-com.
  def host_class(host)
    "host-#{host}".parameterize
  end

  def icon_generated
    variant = ["favicon-mask", "favicon-mask-alt"]
    icon_class = variant[@feed.id % 2]
    span class: "favicon-wrap" do
      span class: "favicon-default #{icon_class}", data: { color_hash_seed: @feed.host || @feed.title } do
        span class: "favicon-inner"
      end
    end
  end
end
