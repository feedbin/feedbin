module Form
  class SelectInputComponent < ApplicationComponent

    slots :input, :label, :accessory_leading

    def view_template
      div(class: "mb-2 text-600", &@label) if label?

      div data: {accessories: class_names(leading: accessory_leading?, trailing: "true")}, class: "select-wrap relative [&_select]:!pr-8 [&[data-accessories~=leading]_select]:!pl-8" do
        if accessory_leading?
          render AccessoryComponent.new(&@accessory_leading)
        end

        render &@input

        render AccessoryComponent.new(position: "trailing") do
          Icon("icon-caret", class: "fill-500 pg-focus:fill-blue-600 pg-disabled:fill-300")
        end
      end
    end

    class AccessoryComponent < ApplicationComponent

      def initialize(position: nil)
        @position = position || "leading"
      end

      def view_template(&block)
        div data: {position: @position}, class: "group pointer-events-none absolute inset-y-0 flex items-center z-10 data-[position=leading]:left-0 data-[position=leading]:pl-2 data-[position=leading]:pl-2 data-[position=trailing]:pr-2 data-[position=trailing]:right-0" do
          yield
        end
      end
    end
  end
end
