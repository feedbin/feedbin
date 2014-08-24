class BasePresenter

  def initialize(object, locals, template)
    @object = object
    @locals = locals
    @template = template
  end

  def favicon(host)
    favicon_classes = ["favicon"]
    if host
      favicon_classes << "favicon-#{host.parameterize}"
    end
    @template.content_tag :span, '', class: "favicon-wrap" do
      @template.content_tag(:span, '', class: favicon_classes.join(" ") )
    end
  end

  def favicon_url(host)
    uri = URI::HTTP.build(
      scheme: "https",
      host: "d34k41xev839cc.cloudfront.net",
      path: "/#{host}"
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