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
      elsif entry && entry.icon
        content = @template.content_tag :span, "", class: "favicon-wrap twitter-profile-image icon-format-round" do
          url = entry.icon
          fallback = @template.image_url("favicon-profile-default.png")
          @template.image_tag_with_fallback(fallback, url, alt: "")
        end
      elsif feed.icon
        content = @template.content_tag :span, "", class: "favicon-wrap twitter-profile-image icon-format-#{feed.custom_icon_format || feed.default_icon_format}" do
          url = feed.icon
          fallback = @template.image_url("favicon-profile-default.png")
          @template.image_tag_with_fallback(fallback, url, alt: "")
        end
      elsif feed.pages?
        content = @template.content_tag :span, "", class: "favicon-wrap collection-favicon" do
          @template.svg_tag("favicon-saved", size: "14x16")
        end
      else
        variant = ["favicon-mask", "favicon-mask-alt"]
        markup = @template.content_tag :span, class: "favicon-default #{variant[feed.id % 2]}", data: { color_hash_seed: feed.host || feed.title } do
          @template.content_tag :span, "", class: "favicon-inner"
        end
        if url = feed.icons.to_a.find { _1.provider_favicon? }&.icon_url
          markup = <<-eos
            <span class="favicon #{feed.favicon.host_class}" style="background-image: url(#{url});"></span>
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
