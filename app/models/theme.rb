class Theme
  attr_accessor :name, :slug
  def initialize(name, slug)
    @name = name
    @slug = slug
  end
end