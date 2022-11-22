class Settings::SelectInputComponent < ViewComponent::Base
  renders_one :label
  renders_one :input
  renders_one :accessory_leading, "Settings::InputAccessoryComponent"
  renders_one :accessory_trailing, "Settings::InputAccessoryComponent"
end