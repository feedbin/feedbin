class ComponentFormBuilder < ActionView::Helpers::FormBuilder
  def radio_button(method, tag_value, options = {})
    super(method, tag_value, merge_defaults(options))
  end

  private

  def merge_defaults(options)
    options[:class] ||= ""
    options[:class] = [options[:class], "peer"].join(" ")
    return options
  end
end