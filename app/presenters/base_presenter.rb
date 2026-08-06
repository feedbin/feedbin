class BasePresenter
  def initialize(object, locals, template)
    @object = object
    @locals = locals
    @template = template
  end

  def favicon(feed, entry = nil)
    @favicon ||= begin
      # The entry list resolves the whole page's Pages favicons up front and
      # hands the map down as a local; a caller rendering one entry has none.
      @template.render FaviconComponent.new(feed:, entry:, favicons: @locals && @locals[:favicons])
    end
  end

  private

  def self.presents(name)
    define_method(name) do
      @object
    end
  end
end
