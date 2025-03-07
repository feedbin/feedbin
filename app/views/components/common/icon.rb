class Common::Icon < ApplicationComponent
  def initialize(name, options = {})
    @name = name
    @options = options
  end

  def view_template(&)
    result = svg_options(@name, @options)
    inline = result.options.delete(:inline)
    svg(**result.options) do |s|
      if inline
        raw safe(result.icon.markup)
      else
        s.use href: "##{@name}"
      end
    end
  end
end
