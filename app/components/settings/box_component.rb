# frozen_string_literal: true

class Settings::BoxComponent < ViewComponent::Base
  renders_one :header
  renders_many :items
end
