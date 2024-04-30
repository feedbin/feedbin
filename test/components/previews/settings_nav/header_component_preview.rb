# frozen_string_literal: true

class SettingsNav::HeaderComponentPreview < Lookbook::Preview
  def default
    render(SettingsNav::HeaderComponent.new) do
      "Header"
    end
  end
end
