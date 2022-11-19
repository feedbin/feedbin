# frozen_string_literal: true

class Settings::SectionHeaderComponentPreview < ViewComponent::Preview
  def default
    render(Settings::SectionHeaderComponent.new)
  end
end
