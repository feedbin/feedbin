class BasePresenter

  def initialize(object, locals, template)
    @object = object
    @locals = locals
    @template = template
  end

  def favicon
    begin
      host = URI::parse(feed.site_url).host.parameterize
    rescue Exception => e
      host = 'none'
    end
    @template.content_tag :span, '', class: 'favicon-wrap' do
      @template.content_tag(:span, '', class: 'favicon-default') +
      @template.content_tag(:span, '', class: "favicon favicon-#{host}")
    end
  end

  private

  def self.presents(name)
    define_method(name) do
      @object
    end
  end

end
