# frozen_string_literal: true

class SettingsNav::NavComponentPreview < Lookbook::Preview
  # @param selected toggle
  def default(selected: false)
    render(SettingsNav::NavComponent.new(title: "Title", subtitle: "Subtitle", url: "#", icon: "menu-icon-settings", selected: selected))
  end
end
