class BasePresenter
  def initialize(object, locals, template)
    @object = object
    @locals = locals
    @template = template
  end

  def favicon(feed)
    @favicon ||= begin
      if feed.newsletter?
        content = @template.content_tag :span, "", class: "favicon-wrap collection-favicon favicon-newsletter-wrap" do
          @template.svg_tag("favicon-newsletter", size: "16x16")
        end
      elsif feed.twitter_user?
        content = @template.content_tag :span, "", class: "favicon-wrap twitter-profile-image" do
          url = @template.camo_link(feed.twitter_user.profile_image_uri_https("bigger"))
          fallback = @template.image_url("favicon-profile-default.png")
          @template.image_tag_with_fallback(fallback, url, alt: "")
        end
      else
        markup = <<-eos
          <span class="favicon favicon-default favicon-character-#{feed.host_letter}" data-host="#{feed.host}"></span>
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
