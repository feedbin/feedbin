# frozen_string_literal: true

class SettingsNav::NavSmallComponent < ViewComponent::Base
  def initialize(url:, method: nil)
    @url = url
    @method = method
  end
end
