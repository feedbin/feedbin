# frozen_string_literal: true

class Settings::DescriptionComponentPreview < ViewComponent::Preview
  def default
    render Settings::DescriptionComponent.new do |component|
      component.title { "Title" }
      component.description { "Description" }
    end
  end
end
