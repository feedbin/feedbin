class SvgIcon
  attr_reader :name, :markup, :width, :height

  def initialize(name, markup, width, height)
    @name = name
    @markup = markup
    @width = width
    @height = height
  end

  def self.new_from_file(file)
    name = File.basename(file, ".svg")
    markup = File.read(file)
    width, height = extract_dimensions(markup)
    if !width || !height
      raise "width or height missing from #{file}"
    end
    new(name, markup, width, height)
  end

  def self.extract_dimensions(markup)
    match = /viewBox\s*=\s*"([^"]*)"/i.match(markup)
    dimensions = match[1].split
    dimensions.last(2)
  end
end

Feedbin::Application.config.icons = begin
  Dir.glob("#{Rails.root}/app/assets/svg/*.svg").sort.each_with_object({}) do |file, hash|
    icon = SvgIcon.new_from_file(file)
    hash[icon.name] = icon
  end
end
