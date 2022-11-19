# frozen_string_literal: true

class SettingsNav::NavSmallComponentPreview < ViewComponent::Preview
  def default
    render(SettingsNav::NavSmallComponent.new(url: "#")) do
      "Home"
    end
  end
end
