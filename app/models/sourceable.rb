class Sourceable
  ATTRIBUTES = %i[title type id section jumpable]

  attr_accessor *ATTRIBUTES

  def initialize(type:, id:, title:, section: nil, jumpable: false)
    @title = title
    @type = type.downcase
    @id = id
    @section = section
    @jumpable = jumpable
  end

  def to_h
    {}.tap do |hash|
      ATTRIBUTES.each do |attribute|
        hash[attribute] = self.send(attribute)
      end
    end
  end
end