class BasePresenter

  def initialize(object, locals, template)
    @object = object
    @locals = locals
    @template = template
  end

  def favicon(feed)
    @favicon ||= begin
      if feed.newsletter?
        content = @template.content_tag :span, '', class: "favicon-wrap collection-favicon favicon-newsletter-wrap" do
          @template.svg_tag('favicon-newsletter', size: "16x16")
        end
      else
        markup = <<-eos
          <span class="favicon favicon-default"></span>
        eos
        if feed.favicon && feed.favicon.cdn_url
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

  def favicon_with_url(host)
    favicon_url = favicon_service_url(host)
    favicon_template(favicon_url)
  end

  def favicon_template(favicon_url)
    @template.content_tag :span, '', class: "favicon-wrap" do
      @template.content_tag(:span, '', class: "favicon", style: "background-image: url(#{favicon_url});")
    end
  end

  def favicon_with_fallback
    if @object.favicon && @object.favicon.cdn_url
      favicon(@object)
    else
      favicon_with_url(@object.host)
    end
  end

  def favicon_service_url(host)
    uri = URI::HTTP.build(
      scheme: "https",
      host: "www.google.com",
      path: "/s2/favicons",
      query: {domain: host}.to_query
    )
    uri.scheme = "https"
    uri.to_s
  end

  private

  def self.presents(name)
    define_method(name) do
      @object
    end
  end

end