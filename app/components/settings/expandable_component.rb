class Settings::ExpandableComponent < BaseComponent
  renders_one :header, "Settings::SectionHeaderComponent"
  renders_one :description
  renders_many :items

  def initialize(capsule: false)
    @capsule = capsule
  end
end
