module Form
  class SelectInputComponent < ApplicationComponent

    slots :input, :label, :accessory_leading

    def template
      render Form::TextInputComponent.new do |input|
        input.label(&@label) if label?
        input.input(&@input)
        input.accessory_trailing do
          render SvgComponent.new "icon-caret", class: "fill-500 pg-focus:fill-blue-600 pg-disabled:fill-300"
        end
        input.accessory_leading(&@accessory_leading)
      end
    end
  end
end
