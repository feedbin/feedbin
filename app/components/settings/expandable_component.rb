class Settings::ExpandableComponent < BaseComponent
  renders_one :header, Settings::H2Component
  renders_one :description
  renders_many :items

  def initialize(options = {})
    @options = options
  end

  def options
    {
      class: ["group [&_[data-item]]:border-0", @options.delete(:class)].reject(&:blank?).join(" "),
      data: {
        controller: "expandable",
        expandable_open_value: "false",
      }.merge(@options.delete(:data) || {})
    }.merge(@options)
  end
end
