module Form
  class TextInputComponent < ApplicationComponent

    slots :input, :label, :accessory_leading, :accessory_trailing

    def view_template
      div(class: "mb-2 text-600", &@label) if label?

      # underscore alternative used because label slot conflicts
      _label data: {accessories: helpers.class_names(leading: accessory_leading?, trailing: accessory_trailing?)}, class: "flex text-input-next items-center gap-2 group items-stretch cursor-text" do
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
      def view_template(&block)
        div class: "pointer-events-none flex flex-center shrink-0" do
          yield
        end
      end
    end
  end
end
