# frozen_string_literal: true

class Settings::HeaderComponentPreview < ViewComponent::Preview
  def default
    render(Settings::HeaderComponent.new) do
      "Header"
    end
  end
end
