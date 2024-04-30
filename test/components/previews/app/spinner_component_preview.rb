# frozen_string_literal: true

class App::SpinnerComponentPreview < Lookbook::Preview
  def default
    render App::SpinnerComponent.new
  end
end
