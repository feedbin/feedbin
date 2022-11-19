class Settings::ControlGroupComponent < BaseComponent
  renders_one :header, "Settings::SectionHeaderComponent"
  renders_many :items
end
