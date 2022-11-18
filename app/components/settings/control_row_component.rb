class Settings::ControlRowComponent < ViewComponent::Base
  include ApplicationHelper
  renders_one :title
  renders_one :description
  renders_one :control
end
