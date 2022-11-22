class Settings::ExpandableComponent < BaseComponent
  renders_one :header, "Settings::SectionHeaderComponent"
  renders_one :description
  renders_many :items
end
