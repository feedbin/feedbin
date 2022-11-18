# frozen_string_literal: true

class Settings::RadioButtonComponentPreview < ViewComponent::Preview
  def default
    render(Settings::RadioButtonComponent.new)
  end
end
