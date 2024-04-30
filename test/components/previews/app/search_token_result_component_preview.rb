# frozen_string_literal: true

class App::SearchTokenResultComponentPreview < Lookbook::Preview
  def default
    render App::SearchTokenResultComponent.new do |token|
      token.icon do
        render SvgComponent.new "icon-search"
      end
      token.text do
        "text"
      end
    end
  end
end
