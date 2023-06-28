# frozen_string_literal: true

class App::ShareFormComponentPreview < Lookbook::Preview
  def default
    render App::ShareFormComponent.new(icon: "icon-search", title: "Title") do |token|
      "Form"
    end
  end
end
