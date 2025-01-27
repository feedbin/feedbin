module App
  class DialogComponent < ApplicationComponent
    STIMULUS_CONTROLLER = :dialog

    def view_template
      div data: stimulus_controller, class: "group" do
        dialog class: dialog_class, data: stimulus_item(target: :dialog, for: STIMULUS_CONTROLLER)
        dialog_template

        # content templates
        render DialogEditSubscriptionComponent.new
      end
    end

    def dialog_template
      template_tag data: stimulus_item(target: :dialog_template, for: STIMULUS_CONTROLLER) do
        div class: "flex flex-col max-h-dvh min-h-dvh sm:min-h-min sm:max-h-[calc(90vh-4rem)]" do
          div class: "shrink-0 h-[env(safe-area-inset-top)]"
          div class: "p-4 native:pt-[5px] text-base flex items-baseline shrink-0 relative border-b" do
            button type: "button", class: "absolute shrink-0 left-0 inset-y-0 px-4 text-600", data: stimulus_item(actions: {click: :close}, for: STIMULUS_CONTROLLER) do
              render SvgComponent.new "icon-close", class: "relative native:top-[-6px] fill-500", title: "Close"
            end
            h2 class: "text-700 grow font-bold m-0 truncate text-center", data: {template: "title"}
          end

          div data: stimulus_item(target: :content, actions: {scroll: :check_scroll}, data: {template: "body"}, for: STIMULUS_CONTROLLER), class: "p-4 overflow-y-scroll overscroll-y-contain grow"
          div data: {template: "footer"}, class: "py-2 sm:py-4 px-4 shrink-0 relative text-right transition-all border-t border-transparent group-data-[dialog-footer-border-value=true]:border-200"
          div data: stimulus_item(target: :footer_spacer, for: STIMULUS_CONTROLLER), class: "shrink-0 transition-all h-[max(var(--visual-viewport-offset),env(safe-area-inset-bottom))]"
        end
      end
    end

    def stimulus_controller
      stimulus(
        controller: STIMULUS_CONTROLLER,
        actions: {
          "click"                         => "clickOutside",
          "dialog:open@window"            => "openWithPurpose",
          "dialog:close@window"           => "close",
          "visual-viewport:change@window" => "delayedCheckScroll"
        },
        values: {
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
        p-0 bg-base text-600 animate-slide-in my-0 mx-auto sm:mt-16

        h-screen w-screen max-h-dvh max-w-[100vw] backdrop:invisible

        sm:max-w-[550px] sm:h-fit sm:w-[calc(100%-32px)] sm:!max-h-[calc(90vh-4rem)]
        sm:rounded-xl sm:shadow-lg sm:backdrop:visible

        backdrop:bg-[rgb(var(--dusk-color-100)/0.4)] backdrop:animate-fade-in
        group-data-[dialog-closing-value=true]:animate-slide-out
        group-data-[dialog-closing-value=true]:backdrop:animate-fade-out
      "
    end

    class Content < ApplicationComponent
      slots :title, :body, :footer

      def initialize(purpose: )
        @purpose = purpose
      end

      def view_template
        template_tag data: stimulus_item(target: :content_template, data: {purpose: @purpose}, for: STIMULUS_CONTROLLER) do
          div data: {dialog_content: "title"}, &@title
          div data: {dialog_content: "body"}, &@body
          div data: {dialog_content: "footer"}, &@footer
        end
      end
    end
  end
end
