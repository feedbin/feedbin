class Settings::ControlGroupComponent < BaseComponent
  renders_one :header, "Settings::SectionHeaderComponent"
  renders_many :items

  def initialize(options = {})
    @options = options
  end
end
