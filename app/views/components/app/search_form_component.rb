module App
  class SearchFormComponent < ApplicationComponent
    def initialize(params:)
      @params = params
    end

    def view_template
      div data: search_component_data, class: "search-wrap grid overflow-hidden min-h-0 group opacity-0 [grid-template-rows:0fr] data-[search-form-visible-value=true]:[grid-template-rows:1fr] data-[search-form-visible-value=true]:opacity-100 data-[search-form-foreground-value=true]:overflow-visible transition-[grid-template-rows]" do
        form_with url: search_entries_path, class: "search-form group min-h-0", remote: true, method: :get, autocomplete: "off", novalidate: true, data: search_form_data do |form|
          form.hidden_field :query_extra, value: "", data: stimulus_item(target: "queryExtra", for: :search_token)
          form.button type: "submit", class: "visually-hidden"
          div class: "text-sm text-600 group relative" do
            div class: "border-b bg-base z-10" do
              div class: "flex flex-row-reverse items-stretch rounded" do
                div class: "mr-2" do
                  render App::SpinnerComponent.new
                end

                form.search_field :query, value: @params[:query], placeholder: "Search", autocorrect: "off", autocapitalize: "off", spellcheck: false , class: "leading-[43px] grow px-2 rounded min-w-0 bg-transparent peer", data: stimulus_item(
                    target: "query focusable", actions: {
                      "keyup" => "keyup",
                      "keydown" => "checkToken",
                      "focus" => "focused",
                    }, for: :search_token
                  ).merge(stimulus_item(target: "query", for: :search_form)
                )

                div class: "shrink-0 flex group ml-2 items-center w-[17px] group-data-[search-token-token-visible-value=true]:tw-hidden" do
                  render SvgComponent.new "icon-search", class: "fill-400 pg-focus:fill-blue-600"
                end

                div class: "grid items-stretch min-h-0 min-w-0 p-1 pr-0 max-w-[40%] [grid-template-columns:0fr] group-data-[search-token-token-visible-value=true]:[grid-template-columns:1fr] transition-[grid-template-columns] overflow-hidden" do
                  button class: "flex min-w-0 items-center text-left gap-2 rounded bg-100 group/token opacity-0 group-data-[search-token-token-visible-value=true]:px-2 group-data-[search-token-token-visible-value=true]:opacity-100 transition duration-200", data_action: "search-token#deleteToken:prevent", title: "Remove filter" do
                    div class: "shrink-0 w-[20px] h-[20px] rounded-[1px] flex items-center justify-center", data: stimulus_item(target: "tokenIcon", for: :search_token)
                    div class: "truncate grow", data: stimulus_item(target: "tokenText", for: :search_token)
                    render SvgComponent.new "icon-close-small", class: "shrink-0 transition fill-400 group-hover/token:fill-600 "
                  end
                end
              end
            end

            div class: "absolute z-50 inset-x-0 top-full w-full origin-top-left p-1 rounded-b bg-base shadow-two focus:outline-none group-data-[search-token-autocomplete-visible-value=false]:tw-hidden" do
              render App::SearchTokenResultComponent.new do |item|
                item.icon do
                  render SvgComponent.new "icon-search", class: "fill-400"
                end
                item.text do
                  plain "Search for "
                  span class: "font-bold", data_search_token_target: "preview"
                  span class: "font-bold before:content-['_in_'] before:font-normal empty:before:tw-hidden", data_search_token_target: "previewSource"
                end
              end

              div data_search_token_target: "results"
            end

            template_tag data_search_token_target: "resultTemplate" do
              render App::SearchTokenResultComponent.new do |item|
                item.icon do
                  render SvgComponent.new "favicon-tag", class: "fill-400"
                end
              end
            end

            template_tag data_search_token_target: "headerTemplate" do
              h2 class: "font-bold mx-2 uppercase mb-2 mt-4 text-500 text-xs", data_template: "text"
            end

            template_tag data_search_token_target: "tagIconTemplate" do
              render SvgComponent.new "favicon-tag", class: "fill-400"
            end
          end
        end

        search_options
      end
    end

    def search_options
      div class: "grid overflow-hidden min-h-0 opacity-0 transition-[grid-template-rows] [grid-template-rows:0fr] group-data-[search-form-options-visible-value=true]:[grid-template-rows:1fr] group-data-[search-form-options-visible-value=true]:opacity-100 group-data-[search-form-options-visible-value=true]:overflow-visible" do
        div class: "min-h-0" do
          div class: "border-b flex gap-2 text-sm p-1 items-stretch" do
            div class: "dropdown-wrap" do
              button class: "flex gap-1 fill-500 items-center p-2 border rounded", data_behavior: "toggle_dropdown" do
                span data_search_form_target: "sortLabel" do
                  "Sort by date"
                end
                render SvgComponent.new "icon-caret-small", class: "relative bottom-[-1px]"
              end
              div class: "dropdown-content" do
                ul do
                  li do
                    button data: stimulus_item(target: "sortOption", actions: {"click" => "changeSearchSort"}, data: {sort_option: "desc"}, for: :search_form) do
                      "Sort by date"
                    end
                  end
                  li do
                    button data: stimulus_item(target: "sortOption", actions: {"click" => "changeSearchSort"}, data: {sort_option: "relevance"}, for: :search_form) do
                      "Sort by relevance"
                    end
                  end
                end
              end
            end
            link_to "Save Search", new_saved_search_path, remote: true, class: "ml-auto !text-600 font-bold hover:no-underline text-xs flex items-center px-2 border border-transparent", data: {behavior: "open_settings_modal", search_form_target: "saveSearch"}
          end
        end
      end
    end

    def search_component_data
      stimulus(
        controller: :search_form,
        actions: {
          "toggle-search@window"        => "toggle",
          "show-search@window"          => "show",
          "hide-search@window"          => "hide",
          "show-search-controls@window" => "showSearchControls",
          "sourceable:selected@window"  => "hide"
        },
        values: {
          visible: "false",
          foreground: "false",
          options_visible: "false",
        },
        outlets: {
          search_token: "[data-controller=search-token]"
        }
      )
    end

    def search_form_data
      stimulus(
        controller: :search_token,
        actions: {
          "click@window"                                 => "clickOff",
          "keydown.up"                                   => "navigate",
          "keydown.down"                                 => "navigate",
          "submit"                                       => "search",
          "sourceable:selected@window"                   => "updateToken",
          "sourceable:source-target-connected@window"    => "buildJumpable",
          "sourceable:source-target-disconnected@window" => "buildJumpable",
        },
        values: {
          token_visible: "false",
          autocomplete_visible: "false",
        },
        outlets: {
          sourceable: "[data-controller=sourceable]"
        },
        data: {
          remote: "true",
          behavior: "search_form"
        }
      )
    end


  end
end