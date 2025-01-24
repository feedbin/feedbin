module App
  class DialogComponent < ApplicationComponent
    slots :content, :title, :body, :footer

    def initialize(purpose:)
      @purpose = purpose
      @stimulus_controller = :dialog
    end

    def view_template
      dialog data: stimulus_controller, class: dialog_class do
        div class: "flex flex-col max-h-dvh min-h-dvh sm:min-h-min sm:max-h-[90vh]" do
          div class: "shrink-0 h-[env(safe-area-inset-top)]"
          div class: "p-4 native:pt-[5px] text-base flex items-baseline shrink-0 relative border-b" do
            if title?
              h2 class: "text-700 grow font-bold m-0 truncate text-center", &@title
            end
            button type: "button", class: "absolute shrink-0 right-0 inset-y-0 pr-4 text-600", data: stimulus_item(actions: {click: :close}, for: @stimulus_controller), aria_label: "Close" do
              "Close"
            end
          end
          div data: stimulus_item(target: :content, actions: {scroll: :check_scroll}, for: @stimulus_controller), class: "px-5 py-4 overflow-y-scroll overscroll-y-contain grow"  do
            render App::ExpandableContainerComponent.new(open: true, selector: :dialog_content) do |expandable|
              expandable.content do
                div class: "pb-4" do
                  render Form::TextInputComponent.new do |input|
                    input.input do
                      input(type: "search", class: "peer text-input", placeholder: "Placeholder")
                    end
                  end
                end
                2.times do
                  p class: "mb-4" do
                    "Lorem ipsum dolor sit amet, consectetur adipisicing elit, sed do eiusmod tempor incididunt ut labore et dolore magna aliqua. Ut enim ad minim veniam, quis nostrud exercitation ullamco laboris nisi ut aliquip ex ea commodo consequat. Duis aute irure dolor in reprehenderit in voluptate velit esse cillum dolore eu fugiat nulla pariatur. Excepteur sint occaecat cupidatat non proident, sunt in culpa qui officia deserunt mollit anim id est laborum."
                  end
                end
              end
            end
          end
          div class: "py-2 sm:py-4 px-4 shrink-0 relative text-right" do
            div class: "absolute left-0 right-0 top-0 h-px bg-200 opacity-0 transition-opacity group-data-[dialog-footer-border-value=true]:opacity-100"
            button data: stimulus_item(actions: {click: :close}, for: @stimulus_controller), class: "button"  do
              "Subscribe"
            end
          end
          div class: "shrink-0 transition-all", style: "height: env(safe-area-inset-bottom);", data: stimulus_item(target: :footer, for: @stimulus_controller)
        end
      end
    end

    def stimulus_controller
      stimulus(
        controller: @stimulus_controller,
        actions: {
          "click" => "clickOutside",
          "dialog:open@window" => "openWithPurpose",
          "dialog:close@window" => "close"
        },
        values: {
          purpose: @purpose,
          closing: "false",
          header_border: "true",
          footer_border: "false",
        },
        outlets: {
          expandable: "[data-controller=expandable]"
        }
      )
    end

    def dialog_class
      "
        group p-0 bg-base text-600 animate-slide-in mt-0 mx-auto sm:mt-16

        h-screen w-screen max-h-dvh max-w-[100vw] backdrop:invisible

        sm:max-w-[550px] sm:h-fit sm:w-[calc(100%-32px)] sm:!max-h-[90vh]
        sm:rounded-xl sm:shadow-lg sm:backdrop:visible

        backdrop:bg-[rgb(var(--dusk-color-100)/0.4)] backdrop:animate-fade-in
        data-[dialog-closing-value=true]:animate-slide-out
        data-[dialog-closing-value=true]:backdrop:animate-fade-out
      "
    end
  end
end
