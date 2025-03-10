module App
  class SearchButtonComponent < ApplicationComponent

    def view_template(&)
      button class: "w-full h-full flex flex-center", data: {
        controller: "event",
        action: "event#dispatch",
        event_identifier_param: "toggle-search",
        title: "Search <i>/</i>",
        toggle: "tooltip",
        html: "true"
      } do
        Icon("icon-search")
      end
    end
  end
end
