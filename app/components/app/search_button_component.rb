class App::SearchButtonComponent < BaseComponent

  def call
    button_tag content, class: "w-full h-full flex flex-center", data: {
      controller: "event",
      action: "event#dispatch",
      event_identifier_param: "toggle-search",
      title: "Search <i>/</i>",
      toggle: "tooltip",
      html: "true"
    } do
      svg_tag "icon-search", size: "16x16"
    end
  end

end
