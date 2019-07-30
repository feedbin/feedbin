class BasePresenter
  def initialize(object, locals, template)
    @object = object
    @locals = locals
    @template = template
  end

  def favicon(feed, entry = nil)
    @favicon ||= begin
      if feed.newsletter?
        content = @template.content_tag :span, "", class: "favicon-wrap collection-favicon" do
          @template.svg_tag("favicon-newsletter", size: "16x16")
        end
      elsif feed.twitter_user?
        content = @template.content_tag :span, "", class: "favicon-wrap twitter-profile-image" do
          url = @template.camo_link(feed.twitter_user.profile_image_uri_https("bigger"))
          fallback = @template.image_url("favicon-profile-default.png")
          @template.image_tag_with_fallback(fallback, url, alt: "")
        end
      elsif feed.icon
        content = @template.content_tag :span, "", class: "favicon-wrap twitter-profile-image" do
          url = @template.camo_link(feed.icon)
          fallback = @template.image_url("favicon-profile-default.png")
          @template.image_tag_with_fallback(fallback, url, alt: "")
        end
      elsif feed.pages? && entry
        icon = Favicon.find_by_host(entry.hostname)
        icon_url = icon&.cdn_url
        if icon_url
          content = @template.content_tag :span, "", class: "favicon-wrap" do
            @template.image_tag(icon_url, alt: "Favicon")
          end
        else
          content = @template.content_tag :span, "", class: "favicon-wrap collection-favicon" do
            @template.svg_tag("favicon-saved", size: "14x16")
          end
        end
      elsif feed.pages?
        content = @template.content_tag :span, "", class: "favicon-wrap collection-favicon" do
          @template.svg_tag("favicon-saved", size: "14x16")
        end
      else
        markup = <<-eos
          <span class="favicon favicon-default favicon-character-#{feed.host_letter}" data-color-hash-seed="#{feed.host}"></span>
        eos
        if feed.favicon&.cdn_url
          markup = <<-eos
            <span class="favicon" style="background-image: url(#{feed.favicon.cdn_url});"></span>
          eos
        end
        content = <<-eos
          <span class="favicon-wrap">
            #{markup}
          </span>
        eos
      end
      content.html_safe
    end
  end

  private

  def self.presents(name)
    define_method(name) do
      @object
    end
  end
end
