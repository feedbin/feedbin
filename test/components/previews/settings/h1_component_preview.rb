# frozen_string_literal: true

class Settings::H1ComponentPreview < ViewComponent::Preview
  def default
    render(Settings::H1Component.new) do
      "Header One"
    end
  end
end
