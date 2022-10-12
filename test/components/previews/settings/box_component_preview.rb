class Settings::BoxComponentPreview < ViewComponent::Preview
  def default
    render Settings::BoxComponent.new do |component|
      component.header { "Setting" }
      component.item do
        content_tag :div, "Control", class: "text-600"
      end
    end
  end
end
