module App
  class SearchButtonComponent < ApplicationComponent

    def template(&)
      button class: "w-full h-full flex flex-center", data: {
        controller: "event",
        action: "event#dispatch",
        event_identifier_param: "toggle-search",
        title: "Search <i>/</i>",
        toggle: "tooltip",
        html: "true"
      } do
        render SvgComponent.new "icon-search"
      end
    end
  end
end
