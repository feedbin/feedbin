# frozen_string_literal: true

class Settings::BoxComponentPreview < ViewComponent::Preview
  def default
    render Settings::BoxComponent.new do |component|
      component.header { "Setting" }
      component.item { "Item One" }
      component.item { "Item Two" }
      component.item { "Item Three" }
    end
  end
end
