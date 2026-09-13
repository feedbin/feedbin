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
    elsif (channel = entry_channel_record) && (channel_url = Image.unified_url(channel.storage_path))
      icon_image(channel_url, format: channel.icon_format)
    elsif (icon_url = @feed.icon_url)
      icon_image(icon_url, format: @feed.icon_format || legacy_icon_format)
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

  # Deploy A only: the proxy on a miss, while the copy backfill runs.
  def icon_twitter_user
    url = @feed.twitter_user.profile_image_uri_https(:original).to_s
    icon_image(Image.avatar_url(url) || RemoteFile.signed_url(url), format: "round")
  end

  # The avatar row of this video's own channel, for entries whose channel is
  # not the feed's -- a playlist feed mixes videos from many channels. When
  # they match, the feed's resolution wins (its own icon row outranks the
  # shared channel avatar).
  def entry_channel_record
    return nil if @entry.nil? || @entry.provider_parent_id.blank?
    return nil if @entry.provider_parent_id == @feed.channel_id
    @entry.channel_image_record
  end

  # One frame for every row-backed icon. format is "round" or "square",
  # read from the row's kind by the caller, never derived from the feed's
  # options. Takes the url rather than re-asking the feed: the legacy
  # fallback inside Feed#icon_url signs the url (an HMAC) on every call.
  def icon_image(url, format:)
    span class: "favicon-wrap icon-#{format}" do
      image_tag_with_fallback(
        image_url("favicon-profile-default.png"),
        url,
        alt: ""
      )
    end
  end

  # Deploy 1 only: a proxy url with no row has no kind to read, so the
  # shape comes from today's derivation over the feed's options. Round is
  # the frame an unset format rendered in before. Goes with the proxy path.
  def legacy_icon_format
    @feed.custom_icon_format || @feed.default_icon_format || "round"
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
