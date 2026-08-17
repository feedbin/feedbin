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
    elsif (icon_url = @feed.icon_url)
      icon_feed(icon_url)
    elsif @feed.pages? && @entry
      icon_pages
    elsif @feed.pages?
      icon_pages_default
    elsif @feed.favicon&.cdn_url
      icon_favicon(@feed.favicon)
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

  def icon_pages
    icon = pages_favicon
    if icon&.cdn_url
      icon_favicon(icon)
    else
      icon_pages_default
    end
  end

  # favicons is the collection-wide map the entry list resolves up front. Fall
  # back to a lookup for the callers that render one entry on its own.
  #
  # host is nullable, so an entry whose url will not parse would otherwise
  # query host IS NULL and bind to an unrelated row.
  def pages_favicon
    hostname = @entry.hostname
    return nil if hostname.blank?
    return @favicons[hostname] if @favicons
    Favicon.find_by_host(hostname)
  end

  def icon_pages_default
    span class: "favicon-wrap collection-favicon" do
      Icon("favicon-saved")
    end
  end

  def icon_favicon(favicon)
    span class: "favicon-wrap" do
      span class: "favicon #{favicon.host_class}", style: "background-image: url(#{favicon.cdn_url});"
    end
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
