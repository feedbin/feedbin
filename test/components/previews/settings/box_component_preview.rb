# frozen_string_literal: true

class Settings::BoxComponentPreview < ViewComponent::Preview
  def default
    render Settings::BoxComponent.new do |component|
      component.with_header { "Setting" }
      component.with_item { "Item One" }
      component.with_item { "Item Two" }
      component.with_item { "Item Three" }
    end
  end
end
