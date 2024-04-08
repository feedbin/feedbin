module Form
  class TextInputNextComponent < ApplicationComponent

    slots :input, :label_slot, :accessory_leading, :accessory_trailing

    def template
      div(class: "mb-2 text-600", &@label_slot) if label_slot?

      label class: "flex text-input-next  items-center gap-2 group items-stretch cursor-text" do
        if accessory_leading?
          render AccessoryComponent.new(&@accessory_leading)
        end

        yield_content &@input

        if accessory_trailing?
          render AccessoryComponent.new(&@accessory_trailing)
        end
      end
    end

    class AccessoryComponent < ApplicationComponent
      def template(&block)
        div class: "pointer-events-none flex flex-center" do
          yield
        end
      end
    end
  end

end
