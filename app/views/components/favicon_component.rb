class FaviconComponent < ApplicationComponent

  def initialize(feed:, entry: nil)
    @feed = feed
    @entry = entry
  end

  def view_template(&)
    if @feed.newsletter?
      icon_newsletter
    elsif @feed.twitter_user?
      icon_twitter_user
    elsif @feed.icon
      icon_feed
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
      render SvgComponent.new("favicon-newsletter")
    end
  end

  def icon_twitter_user
    span class: "favicon-wrap twitter-profile-image" do
      helpers.image_tag_with_fallback(
        helpers.image_url("favicon-profile-default.png"),
        RemoteFile.camo_url(@feed.twitter_user.profile_image_uri_https(:original)),
        alt: ""
      )
    end
  end

  def icon_feed
    span class: "favicon-wrap twitter-profile-image icon-format-#{@feed.custom_icon_format || @feed.default_icon_format}" do
      helpers.image_tag_with_fallback(
        helpers.image_url("favicon-profile-default.png"),
        RemoteFile.camo_url(@feed.icon),
        alt: ""
      )
    end
  end

  def icon_pages
    icon = Favicon.find_by_host(@entry.hostname)
    if icon&.cdn_url
      icon_favicon(icon)
    else
      icon_pages_default
    end
  end

  def icon_pages_default
    span class: "favicon-wrap collection-favicon" do
      render SvgComponent.new("favicon-saved")
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
