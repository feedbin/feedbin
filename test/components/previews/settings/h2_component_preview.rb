# frozen_string_literal: true

class Settings::H2ComponentPreview < Lookbook::Preview
  def default
    render(Settings::H2Component.new) do
      "Header Two"
    end
  end
end
