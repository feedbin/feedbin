class BasePresenter
  def initialize(object, locals, template)
    @object = object
    @locals = locals
    @template = template
  end

  def favicon(feed, entry = nil)
    @favicon ||= begin
      @template.render FaviconComponent.new(feed:, entry:)
    end
  end

  private

  def self.presents(name)
    define_method(name) do
      @object
    end
  end
end
