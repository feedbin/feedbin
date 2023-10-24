module Settings
  class ExpandableComponent < ApplicationComponent

    slots :header, :description

    def initialize(attributes = {})
      @attributes = attributes
      @items = []
    end

    def template
      render App::ExpandableContainerComponent.new do |expandable|
        render Settings::ControlGroupComponent.new(**attributes) do |group|
          group.header(&@header)
          group.item(&@description)
          group.item do
            expandable.content do
              ul class: "border-t" do
                @items.each {render _1}
              end
            end
          end
        end
      end
    end

    def item(...)
      @items << ItemComponent.new(...)
    end

    private

    def attributes
      mix({class: "group [&_[data-item]]:border-0"}, @attributes)
    end

    class ItemComponent < ApplicationComponent
      def template(&)
        li(class: "border-b last:border-b-0", &)
      end
    end
  end
end
