module Dialog
  class Template < ApplicationComponent
    STIMULUS_CONTROLLER = :dialog

    def view_template
      stimulus_controller = stimulus(
        controller: STIMULUS_CONTROLLER,
        actions: {
          "click"                         => "clickOutside",
          "dialog:open@window"            => "openWithPurpose",
          "dialog:update@window"          => "updateContent",
          "dialog:close@window"           => "close",
          "visual-viewport:change@window" => "delayedCheckScroll"
        },
        values: {
          closing: "false",
          header_border: "true",
          footer_border: "false",
          footer: "true"
        },
        outlets: {
          expandable: "[data-controller=expandable]"
        }
      )

      dialog_class = "
        p-0 sm:pt-[64px] text-600 my-0 mx-auto bg-transparent animate-slide-in sm:animate-slide-in-top overflow-visible

        h-screen w-screen max-h-dvh max-w-[100vw] backdrop:invisible sm:backdrop:visible

        sm:max-w-[550px] sm:h-fit sm:w-[calc(100%-32px)]

        backdrop:bg-[rgb(var(--dusk-color-100)/0.4)] backdrop:animate-fade-in

        group-data-[dialog-closing-value=true]:animate-slide-out
        sm:group-data-[dialog-closing-value=true]:animate-slide-out-top

        group-data-[dialog-closing-value=true]:backdrop:animate-fade-out
      "

      div data: stimulus_controller, class: "group" do
        dialog class: dialog_class, data: stimulus_item(target: :dialog, for: STIMULUS_CONTROLLER) do
          div class: "h-dvh overflow-y-scroll snap-y snap-mandatory hide-scrollbar overscroll-none sm:h-auto sm:overflow-y-visible sm:snap-none sm:overscroll-auto", data: stimulus_item(target: :snap_container, for: STIMULUS_CONTROLLER) do
            div class: "snap-start h-dvh sm:tw-hidden"
            div class: "snap-start h-dvh sm:snap-align-none sm:h-auto" do
              div class: "bg-base shadow-border-top sm:rounded-xl sm:shadow-lg", data: stimulus_item(target: :dialog_content, for: STIMULUS_CONTROLLER)
            end
          end
        end
      end
    end


    class Content < ApplicationComponent
      slots :title, :body, :footer

      def initialize(dialog_id:)
        @dialog_id = dialog_id
      end

      def view_template
        template_tag data: {dialog_id: @dialog_id} do
          div class: "flex flex-col max-h-dvh min-h-dvh sm:overflow-hidden sm:min-h-0 sm:max-h-[calc(100vh-128px)]" do
            div class: "shrink-0 h-[env(safe-area-inset-top)]"
            div class: "p-4 native:pt-[5px] text-base flex items-baseline shrink-0 relative border-b border-transparent group-data-[dialog-header-border-value=true]:border-200" do
              button type: "button", class: "absolute shrink-0 left-0 inset-y-0 px-4 text-600", data: stimulus_item(actions: {click: :close}, for: STIMULUS_CONTROLLER) do
                render SvgComponent.new "icon-close", class: "relative native:top-[-6px] fill-600", title: "Close"
              end
              h2 class: "text-700 grow font-bold m-0 truncate text-center", &@title
            end

            div data: stimulus_item(target: :content, actions: {scroll: :check_scroll}, data: {template: "body"}, for: STIMULUS_CONTROLLER), class: "p-4 overflow-y-scroll overscroll-y-contain grow relative transition-[height] duration-300", &@body
            div data: {template: "footer"}, class: "py-2 sm:py-4 px-4 shrink-0 relative text-right transition-all border-t border-transparent group-data-[dialog-footer-border-value=true]:border-200 #{footer? ? "" : "tw-hidden"}", &@footer
            div data: stimulus_item(target: :footer_spacer, for: STIMULUS_CONTROLLER), class: "shrink-0 transition-all h-[max(var(--visual-viewport-offset),env(safe-area-inset-bottom))] group-data-[dialog-footer-value=false]:tw-hidden #{footer? ? "" : "tw-hidden"}"
          end
        end
      end
    end

    class Placeholder < ApplicationComponent
      slots :title

      def initialize(dialog_id:, title:)
        @dialog_id = dialog_id
        @title = title
      end

      def view_template
        render Content.new(dialog_id: @dialog_id) do |content|
          content.title { @title }
          content.body do
            div(class: "inset-0 absolute sm:static flex flex-center text-500") do
              p class: "sm:py-40" do
                "Loading…"
              end
            end
          end
        end
      end
    end
  end
end
