# frozen_string_literal: true

class SettingsNav::HeaderComponentPreview < ViewComponent::Preview
  def default
    render(SettingsNav::HeaderComponent.new) do
      "Header"
    end
  end
end
