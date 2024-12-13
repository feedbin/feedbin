module Site
  class DialogComponent < ApplicationComponent
    slots :content, :title, :body, :footer

    def initialize
      @stimulus_controller = :dialog
    end

    def view_template
      dialog data: stimulus(controller: @stimulus_controller, actions: {"click" => "clickOutside", "dialog:open@window" => "open"}, values: { closing: "false", header_border: "true", footer_border: "false" }), class: dialog_class do
        div class: "flex flex-col max-h-[90vh]" do
          div class: "p-4 shrink-0 relative border-b" do
            if title?
              h2 class: "font-bold m-0 truncate pr-[56px]", &@title
            end
            button type: "button", class: "flex items-center absolute inset-y-0 right-0 w-[40px]", data: stimulus_item(actions: {click: :close}, for: @stimulus_controller), aria_label: "Close" do
              render SvgComponent.new "icon-close-small", class: "fill-500 relative left-[15px]"
            end
          end
          div data: stimulus_item(target: :content, actions: {scroll: :check_scroll}, for: @stimulus_controller), class: "px-5 py-4 overflow-y-scroll overscroll-y-contain"  do
            2.times do
              p class: "mb-4" do
                "Lorem ipsum dolor sit amet, consectetur adipisicing elit, sed do eiusmod tempor incididunt ut labore et dolore magna aliqua. Ut enim ad minim veniam, quis nostrud exercitation ullamco laboris nisi ut aliquip ex ea commodo consequat. Duis aute irure dolor in reprehenderit in voluptate velit esse cillum dolore eu fugiat nulla pariatur. Excepteur sint occaecat cupidatat non proident, sunt in culpa qui officia deserunt mollit anim id est laborum."
              end
            end
          end
          div class: "bg-white p-4 shrink-0 relative text-right" do
            div class: "absolute left-0 right-0 top-0 h-px bg-200 opacity-0 transition-opacity group-data-[dialog-footer-border-value=true]:opacity-100"
            button data: stimulus_item(actions: {click: :close}, for: @stimulus_controller), class: "px-6 py-3 text-base font-medium text-white bg-blue-600 rounded"  do
              "Close"
            end
          end
        end
      end
    end

    def dialog_class
      %(group p-0 max-w-[550px] w-[calc(100%-32px)] max-h-[90vh] border border-600 rounded-lg shadow-lg animate-slide-in
        backdrop:bg-700/70 backdrop:backdrop-blur backdrop:animate-fade-in
        data-[dialog-closing-value=true]:animate-slide-out
        data-[dialog-closing-value=true]:backdrop:animate-fade-out)
    end
  end
end
