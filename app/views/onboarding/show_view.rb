module Onboarding
  class ShowView < ApplicationComponent

    STIMULUS_CONTROLLER = :onboarding__main

    def view_template
      stimulus_controller = stimulus(
        controller: STIMULUS_CONTROLLER,
        values: {
          step: :welcome,
          path: nil,
          animate: "true",
          import_started: "false",
          save_url: onboarding_path,
        },
        actions: {
          "upload:uploaded@window" => "importStarted",
        },
      )

      div data: stimulus_controller, class: "select-none group h-full w-full flex flex-col" do
        div class: "flex shrink-0 flex-center p-3 relative bg-base" do
          div class: "text-700 text-[15px] font-bold" do
            "Get Started"
          end
          button type: "button", class: "absolute shrink-0 right-0 inset-y-0 px-4 text-600", data: stimulus_item(actions: {click: :close}, for: STIMULUS_CONTROLLER) do
            Icon("icon-close", class: "relative fill-600", title: "Close")
          end
        end
        div class: "flex flex-center grow bg-100 border-t min-h-0" do
          div class: "h-full flex flex-col min-w-0 md:w-[550px] md:max-h-[750px] min-h-0" do
            div class: "bg-base md:border md:rounded-xl min-w-0 flex flex-col min-h-0 grow h-full min-h-0" do
              div data: stimulus_item(target: :viewport, for: STIMULUS_CONTROLLER), class: "relative grow min-h-0 w-full h-full overflow-hidden focus:outline-none" do
                div data: stimulus_item(target: :scroll_track, for: STIMULUS_CONTROLLER), class: "flex h-full min-h-0 transition-transform duration-300 group-data-[onboarding--main-animate-value=false]:duration-0 will-change-transform ease-in-out" do
                  [:welcome, :add, :import, :extension].each do |panel|
                    send(panel)
                  end
                end
              end
              div class: "px-4 sm:px-4 h-[77px] flex items-center shrink-0 relative border-t group-data-[onboarding--main-step-value=welcome]:opacity-0" do
                button class: "button button-secondary shrink-0", data: stimulus_item(actions: {click: :back}, for: STIMULUS_CONTROLLER) do
                  "Back"
                end

                # only shown for import
                button class: "ml-auto button group-data-[onboarding--main-path-value=add]:tw-hidden group-data-[onboarding--main-step-value=extension]:tw-hidden group-data-[onboarding--main-import-started-value=false]:tw-hidden", data: stimulus_item(target: :continue_button, actions: {click: :continue}, for: STIMULUS_CONTROLLER) do
                  "Continue"
                end

                # only shown for add
                button class: "ml-auto button group-data-[onboarding--main-path-value=import]:tw-hidden group-data-[onboarding--main-step-value=extension]:tw-hidden", data: stimulus_item(target: :continue_button, actions: {click: :continue}, for: STIMULUS_CONTROLLER) do
                  "Continue"
                end

                button class: "ml-auto button tw-hidden group-data-[onboarding--main-step-value=extension]:block", data: stimulus_item(actions: {click: :close}, for: STIMULUS_CONTROLLER) do
                  "Done"
                end
              end
            end
          end
        end
      end
    end

    def welcome
      render PanelView.new(panel: :welcome) do
        div class: "flex flex-center flex-col h-full" do
          Icon("logo-dynamic", class: "w-[54px] h-auto mb-4")
          div class: "text-2xl text-700 font-bold mb-10" do
            "Welcome to Feedbin"
          end

          div class: "flex flex-col gap-4 w-full" do
            big_button(
              title: "Import Subscriptions",
              subtitle: "Import an OPML file from another service",
              icon: "menu-icon-import-export",
              panel: :import
            )
            big_button(
              title: "Browse Feeds",
              subtitle: "Choose feeds to add ",
              icon: "icon-search",
              panel: :add
            )
            div class: "pt-6 flex flex-center shrink-0 relative" do
              button class: "text-blue-600", data: stimulus_item(actions: {click: :close}, for: STIMULUS_CONTROLLER) do
                "Skip"
              end
            end
          end
        end
      end
    end

    def add
      controller = :onboarding__subscriptions
      render PanelView.new(panel: :add, padding: false, attributes: {class: "tw-hidden group-data-[onboarding--main-path-value=add]:block"}) do
        form_with url: onboarding_subscriptions_path, method: :patch, data: stimulus(controller: controller, values: {selected_count: 0}, data: {remote: true}), class: "group flex flex-col h-full min-h-0" do
          div class: "flex gap-4 justify-between items-baseline w-full p-4 pb-4 shrink-0 bg-base rounded-t-xl sticky top-0" do
            div class: "text-xl font-bold" do
              "Add Content"
            end
            button data: stimulus_item(actions: {click: :clear_all} , for: controller), class: "text-500 group-data-[onboarding--subscriptions-selected-count-value=0]:tw-hidden" do
              plain "Clear All ("
              span data: stimulus_item(target: :count, for: controller)
              plain ")"
            end
          end
          div class: "min-h-0 flex-1 px-4 pt-1" do
            div class: "grid grid-cols-2 sm:grid-cols-3 gap-4 pb-4" do
              Feedbin::Application.config.onboarding_feeds.shuffle.each do |feed|
                tile(feed: feed, controller: controller)
              end
            end
          end
        end
      end
    end

    def extension
      render PanelView.new(panel: :extension) do
        div class: "flex flex-col gap-4" do

          div class: "text-xl font-bold" do
            "Get the Extension"
          end

          img src: asset_path("extension-promo"), class: "rounded"

          div class: "font-bold" do
            "Subscribe to feeds, newsletters, and save pages to Feedbin"
          end
          ul class: "pl-[40px] list-disc [&_li]:[list-style:disc] flex flex-col gap-2" do
            li do
              "Subscribe to feeds in Feedbin while browsing the web"
            end
            li do
              "Save the page you‘re on to read later"
            end
            li do
              "Create email addresses for newsletter subscriptions"
            end
          end
          button class: "button button-secondary" do
            "Get for Safari"
          end

        end
      end
    end

    def import
      controller = :upload
      render PanelView.new(panel: :import, attributes: {class: "tw-hidden group-data-[onboarding--main-path-value=import]:block"}) do
        div class: "w-full h-full", data: {behavior: "onboarding_import"} do
          div class: "w-full h-full group", data: stimulus(controller: controller, values: {dragging: false, dropped: false, error: false}, actions: { "upload:serverError@window" => "serverError"}) do
            input(
              type: "file",
              accept: ".opml,.xml",
              class: "hidden",
              name: "import[upload]",
              data: stimulus_item(target: :file_input, actions: {change: :file_selected}, for: controller)
            )
            form_with class: "w-full h-full group", model: Import.new, url: helpers.onboarding_imports_path, method: :post, data: stimulus_item(target: :form, data: {remote: true}, for: controller) do |form|
              form.hidden_field :filename, data: stimulus_item(target: :filename_field, for: controller)
              form.hidden_field :xml, data: stimulus_item(target: :xml_field, for: controller)
              div data: stimulus_item(target: :dropzone, actions: {dragover: :drag_over, dragleave: :drag_leave, drop: :drop, dragstart: :drag_start }, for: controller), class: "w-full h-full border rounded-xl border-dashed flex flex-center transition-colors group-data-[upload-dragging-value=true]:border-blue-700 group-data-[upload-dragging-value=true]:bg-blue-300 group-data-[upload-error-value=true]:border-red-600 group-data-[upload-error-value=true]:bg-red-300" do
                div class: "flex flex-col gap-4 flex-center group-data-[upload-error-value=true]:tw-hidden" do
                  Icon("icon-cloud", class: "fill-600")
                  div class: "" do
                    "Drag & Drop OPML Here"
                  end
                  div class: "font-bold" do
                    "OR"
                  end
                  button data: stimulus_item(actions: {click: :choose_file}, for: controller), type: "button", class: "button button-secondary" do
                    "Choose File"
                  end
                end
                div class: "flex-col gap-4 tw-hidden flex-center group-data-[upload-error-value=true]:flex" do
                  div data: stimulus_item(target: :error_message, for: controller)
                end
              end
            end
          end
        end
      end
    end

    def tile(feed:, controller:)
      label class: "block rounded-lg border border p-3 hover:border-300 min-w-0 transition cursor-pointer text-sm text-left outline outline-2 outline-transparent transition-[outline-color] [&:has(:checked)]:border-blue-600 [&:has(:checked)]:outline-blue-600" do
        input type: "hidden", name: "feed_url[#{feed[:feed_url]}]", value: "0"
        input type: "checkbox", name: "feed_url[#{feed[:feed_url]}]", value: feed[:feed_url], data: stimulus_item(target: :feed, actions: {change: :update_selection}, for: controller)
        img src: asset_path("suggested-sites/#{feed[:image]}"), class: "border rounded mb-2"
        div class: "font-medium truncate" do
          feed[:title]
        end
        div class: "text-500 text-xs truncate" do
          feed[:host]
        end
      end
    end

    def big_button(title:, subtitle:, icon:, panel:)
      button data: stimulus_item(actions: {click: :panel_selected}, params: {panel: panel, set_path: "true"}, for: STIMULUS_CONTROLLER), class: "border rounded-xl flex items-center gap-4 p-4 grow text-left" do
        div class: "w-[30px] flex flex-center shrink-0" do
          Icon(icon, class: "fill-500")
        end

        div class: "grow min-w-0 flex flex-col items-start text-600" do
          div class: "font-bold" do
            title
          end
          div class: "text-500" do
            subtitle
          end
        end

        div class: "w-[30px] flex flex-center shrink-0" do
          Icon("icon-caret", class: "fill-500 -rotate-90")
        end
      end
    end

    class PanelView < ApplicationComponent
      def initialize(panel:, padding: true, attributes: {})
        @panel = panel
        @padding = padding
        @attributes = attributes
      end

      def view_template
        div data: stimulus_item(target: :panel, for: STIMULUS_CONTROLLER, data: {panel: @panel}), **mix({ class: "flex-none w-full min-w-full h-full" }, @attributes) do
          div class: "h-full overflow-y-auto #{@padding ? "p-4" : ""}" do
            yield
          end
        end
      end
    end
  end
end
