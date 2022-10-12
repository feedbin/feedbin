class Settings::ControlTextComponent < ViewComponent::Base
  renders_one :title
  renders_one :description
  renders_one :control
end
