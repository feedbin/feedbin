class Settings::ControlGroupComponent < BaseComponent
  renders_one :header, Settings::H2Component
  renders_one :description
  renders_many :items, "ItemComponent"

  def initialize(options = {})
    @options = options
  end

  def options
    {
      class: [@options.delete(:class)].reject(&:blank?).join(" "),
    }.merge(@options)
  end

  class ItemComponent < BaseComponent
    def initialize(options = {})
      @options = options
    end

    def call
      options = {
        class: [classes, @options.delete(:class)].reject(&:blank?).join(" "),
        data: data.merge(@options.delete(:data) || {})
      }.merge(@options)
      content_tag :div, content, options
    end

    private

    def classes
      "border-b last:border-b-0"
    end

    def data
      {
        item: true
      }
    end
  end
end



