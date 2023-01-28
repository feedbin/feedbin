class Form::TextInputComponent < BaseComponent
  renders_one :label
  renders_one :input
  renders_one :accessory_leading, Form::InputAccessoryComponent
  renders_one :accessory_trailing, Form::InputAccessoryComponent
  renders_one :accessory_leading_cap, Form::InputCapComponent
  renders_one :accessory_trailing_cap, Form::InputCapComponent
end
