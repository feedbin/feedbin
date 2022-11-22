# frozen_string_literal: true

class Settings::ExpandableComponentPreview < ViewComponent::Preview
  def default
    render(Settings::ExpandableComponent.new)
  end
end
