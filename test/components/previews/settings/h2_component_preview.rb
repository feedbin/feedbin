class Settings::H2ComponentPreview < ViewComponent::Preview
  def default
    render(Settings::H2Component.new) do
      "Header Two"
    end
  end
end
