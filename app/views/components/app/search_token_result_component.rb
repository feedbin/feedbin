module App
  class SearchTokenResultComponent < ApplicationComponent
    slots :icon, :text

    def view_template
      button(class: "flex items-center gap-2 w-full text-left rounded p-2 hover:bg-100 focus:bg-100", data_search_token_target: "focusable", data_action: "search-token#tokenSelected", data_search_token_index_param: "" ) do
        div(class: "shrink-0 w-[20px] h-[20px] rounded-[1px] flex items-center justify-center", data_template: "icon", &@icon)
        div(class: "truncate grow", data_template: "text", &@text)
      end
    end
  end
end
