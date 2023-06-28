# frozen_string_literal: true

class App::SearchButtonComponentPreview < Lookbook::Preview
  def default
    render App::SearchButtonComponent.new
  end
end
