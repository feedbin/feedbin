# frozen_string_literal: true

class Settings::ControlGroupComponent < ViewComponent::Base
  renders_one :header
  renders_many :items
end
