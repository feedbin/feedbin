# frozen_string_literal: true

class Settings::CheckBoxComponentPreview < ViewComponent::Preview
  def default
    render(Settings::CheckBoxComponent.new)
  end
end
