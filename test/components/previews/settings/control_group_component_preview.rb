class Settings::ControlGroupComponentPreview < ViewComponent::Preview
  def default
    render Settings::ControlGroupComponent.new do |component|
      component.header { "Setting" }
      component.item do
        content_tag :div, "Control", class: "text-600"
      end
    end
  end
end
