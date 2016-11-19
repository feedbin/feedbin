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
        style = nil
        if feed.favicon && feed.favicon.cdn_url
          style = "background-color: transparent !important; background-image: url(#{feed.favicon.cdn_url});"
        end
        content = <<-eos
          <span class="favicon-wrap">
            <span class="favicon" style="#{style}"></span>
          </span>
        eos
      end
      content.html_safe
    end
  end

  def favicon_with_url(host)
    @template.content_tag :span, '', class: "favicon-wrap" do
      @template.content_tag(:span, '', class: "favicon", style: "background-image: url(#{favicon_url(host)});")
    end
  end

  def favicon_url(host)
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