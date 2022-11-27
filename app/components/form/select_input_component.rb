class Form::SelectInputComponent < ViewComponent::Base
  renders_one :label
  renders_one :input
  renders_one :accessory_leading, "Form::InputAccessoryComponent"
  renders_one :accessory_trailing, "Form::InputAccessoryComponent"
end
