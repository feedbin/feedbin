module Settings
  class ControlGroupComponent < ApplicationComponent

    slots :description

    def initialize(options = {})
      @options = options
      @items = []
    end

    def template
      div(**@options) do
        render(@header) if @header
        if @items.present?
          div(class: "border-y flex flex-col group-data-[capsule=true]:border group-data-[capsule=true]:rounded-lg group-data-[item-capsule=true]:border-0 group-data-[item-capsule=true]:gap-2", data: {item_container: "true"}) do
            @items.each {render _1}
          end
        end
        div(class: "text-sm text-500 mt-2", &@description) if @description
      end
    end

    def header(...)
      @header = H2Component.new(...)
    end

    def item(...)
      @items << ItemComponent.new(...)
    end

    class ItemComponent < ApplicationComponent
      def initialize(attributes = {})
        @attributes = attributes
      end

      def template(&)
        div(**attributes, &)
      end

      private

      def attributes
        mix({class: "border-b last:border-b-0 group-data-[item-capsule=true]:border-0", data: {item: "true"}}, @attributes)
      end
    end
  end
end
