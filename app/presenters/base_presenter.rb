class BasePresenter

  def initialize(object, locals, template)
    @object = object
    @locals = locals
    @template = template
  end

  def favicon(host)
    @favicon ||= begin
      favicon_classes = ["favicon"]
      if host
        favicon_classes << "favicon-#{host.gsub('.', '-')}"
      end
      classes = favicon_classes.join(" ")
      content = <<-eos
        <span class="favicon-wrap">
          <span class="#{classes}"></span>
        </span>
      eos
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