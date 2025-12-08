module Onboarding
  class ShowView < ApplicationComponent
    TITLE = "Get Started"
    SITES = [
      {
        title: "Ars Technica",
        host: "arstechnica.com",
        image: "suggested-arstechnica.png"
      },
      {
        title: "Daring Fireball",
        host: "daringfireball.net",
        image: "suggested-daringfireball.png",
      },
      {
        title: "Feedbin",
        host: "feedbin.com",
        image: "suggested-feedbin.png",
      },
      {
        title: "Kottke",
        host: "kottke.org",
        image: "suggested-kottke.png",
      },
      {
        title: "MacStories",
        host: "www.macstories.net",
        image: "suggested-macstories.png",
      },
      {
        title: "Marques Brownlee",
        host: "@mkbhd",
        image: "suggested-mkbhd.png",
      },
      {
        title: "Polygon",
        host: "www.polygon.com",
        image: "suggested-polygon.png",
      },
      {
        title: "Six Colors",
        host: "sixcolors.com",
        image: "suggested-sixcolors.png",
      },
      {
        title: "Spyglass",
        host: "spyglass.org",
        image: "suggested-spyglass.png",
      },
      {
        title: "Stratechery",
        host: "stratechery.com",
        image: "suggested-stratechery.png",
      },
      {
        title: "The Oatmeal",
        host: "theoatmeal.com",
        image: "suggested-theoatmeal.png",
      },
      {
        title: "The Verge",
        host: "www.theverge.com",
        image: "suggested-theverge.png",
      },
      {
        title: "Wirecutter",
        host: "www.nytimes.com",
        image: "suggested-wirecutter.png",
      },
      {
        title: "xkcd.com",
        host: "xkcd.com",
        image: "suggested-xkcd.png",
      }
    ]

    STIMULUS_CONTROLLER = :onboarding__main

    def initialize
    end

    def view_template
      div data: stimulus(controller: STIMULUS_CONTROLLER, values: {step: :welcome}), class: "group border rounded-xl w-[456px] h-[700px] flex flex-col" do
        div class: "p-4 sm:px-6 native:pt-[5px] flex items-baseline shrink-0 relative border-b" do
          button class: "shrink-0" do
            "Back"
          end
          div class: "text-700 grow font-bold m-0 truncate text-center" do
            "Get Started"
          end
          button type: "button", class: "absolute shrink-0 right-0 inset-y-0 px-4 sm:px-6 text-600", data: stimulus_item(actions: {click: :close}, for: STIMULUS_CONTROLLER) do
            Icon("icon-close", class: "relative native:top-[-6px] fill-600", title: "Close")
          end
        end
        div class: "relative grow min-h-0 w-full h-full overflow-hidden focus:outline-none" do
          div class: "flex h-full transition-transform duration-500 ease-[cubic-bezier(0.22,0.61,0.36,1)] will-change-transform" do
            [:welcome, :add, :import, :extension].each do |page|
              div class: "flex-none w-full min-w-full h-full" do
                div class: "h-full box-border p-6 overflow-y-auto" do
                  send(page)
                end
              end
            end
          end
        end
        div class: "px-4 sm:px-6 h-[77px] flex items-center shrink-0 relative border-t" do
          div class: "tw-hidden group-data-[onboarding--main-step-value=welcome]:flex grow flex-center" do
            button class: "text-blue-600" do
              "Skip"
            end
          end
          div class: "block group-data-[onboarding--main-step-value=welcome]:tw-hidden" do
            button class: "ml-auto button" do
              "Continue"
            end
          end
        end
      end
    end

    def welcome
      div class: "flex flex-center flex-col h-full" do
        Icon("logo-dynamic", class: "w-[54px] h-auto mb-4")
        div class: "text-2xl text-700 font-bold mb-10" do
          "Welcome to Feedbin"
        end

        div class: "flex flex-col gap-4 w-full" do
          big_button(
            title: "Import Subscriptions",
            subtitle: "Import an OPML file from another service",
            icon: "menu-icon-import-export"
          )
          big_button(
            title: "Browse Feeds",
            subtitle: "Choose feeds to add ",
            icon: "icon-search"
          )
        end
      end
    end

    def add
      controller = :onboarding__subscriptions
      div data: stimulus(controller: controller, values: {selected_count: 0}), class: "group flex flex-col h-full overflow-y-auto min-h-0 hide-scrollbar" do
        div class: "flex gap-4 justify-between items-baseline w-full pb-4 shrink-0 bg-base sticky top-0" do
          div class: "text-xl font-bold" do
            "Add Content"
          end
          button data: stimulus_item(actions: {click: :clear_all} , for: controller), class: "text-500 group-data-[onboarding--subscriptions-selected-count-value=0]:tw-hidden" do
            plain "Clear All ("
            span data: stimulus_item(target: :count, for: controller)
            plain ")"
          end
        end
        div class: "grid grid-cols-2 sm:grid-cols-3 gap-4 min-h-0 p-[2px] flex-1" do
          SITES.shuffle.each do
            tile(title: it[:title], subtitle: it[:host], image: it[:image], controller: controller)
          end
        end
      end
    end

    def extension
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

    def import
      controller = :upload
      div class: "w-full h-full overflow-y-auto hide-scrollbar", data: {behavior: "onboarding_import"} do
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
            div data: stimulus_item(target: :dropzone, actions: {dragover: :drag_over, dragleave: :drag_leave, drop: :drop, dragstart: :drag_start }, for: controller), class: "w-full h-full border rounded-xl border-dashed flex flex-center transition-colors group-data-[upload-dragging-value=true]:border-blue-700 group-data-[upload-dragging-value=true]:bg-[rgb(var(--color-blue-400)/0.1)] group-data-[upload-error-value=true]:border-red-600 group-data-[upload-error-value=true]:bg-[rgb(var(--color-red-600)/0.1)]" do
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

    def tile(title:, subtitle:, image:, controller:)
      label class: "block rounded-lg border border p-3 hover:border-300 min-w-0 transition cursor-pointer text-sm text-left outline outline-2 outline-transparent transition-[outline-color] [&:has(:checked)]:border-blue-600 [&:has(:checked)]:outline-blue-600" do
        input type: "checkbox", data: stimulus_item(target: :feed, actions: {change: :update_selection}, for: controller)
        img src: asset_path("suggested-sites/#{image}"), class: "border rounded mb-2"
        div class: "font-medium truncate" do
          title
        end
        div class: "text-500 text-xs truncate" do
          subtitle
        end
      end
    end

    def big_button(title:, subtitle:, icon:)
      button class: "border rounded-xl flex items-center gap-4 p-4 grow text-left" do
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

  end
end
