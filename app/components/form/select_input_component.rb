class Form::SelectInputComponent < Form::TextInputComponent
  def accessory_trailing
    super(position: "trailing") do
      svg_tag "icon-caret", class: "fill-500 pg-focus:fill-blue-600 pg-disabled:fill-200"
    end
  end

  def accessory_trailing?
    true
  end
end
