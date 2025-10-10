module Form
  class TextInputComponent < ApplicationComponent

    slots :input, :label_content, :accessory_leading

    def view_template
      div(class: "mb-2 text-600", &@label_content) if label_content?

      label data: {accessories: class_names(leading: accessory_leading?, trailing: accessory_trailing?)}, class: "flex text-input-next items-center gap-2 group items-stretch cursor-text" do
        if accessory_leading?
          render AccessoryComponent.new(&@accessory_leading)
        end

        render &@input

        if accessory_trailing?
          render @accessory_trailing
        end
      end
    end

    def accessory_trailing(interactive: false, &block)
      @accessory_trailing = AccessoryComponent.new(interactive: interactive, &block)
    end

    def accessory_trailing?
      @accessory_trailing ? true : false
    end

    class AccessoryComponent < ApplicationComponent
      def initialize(interactive: false)
        @interactive = interactive
      end

      def view_template(&block)
        div class: "#{@interactive ? "" : "pointer-events-none"} flex flex-center shrink-0" do
          yield
        end
      end
    end
  end
end
