module Onboarding
  class ShowView < ApplicationView
    def initialize()
    end

    def view_template
      div class: "flex flex-wrap gap-4 p-2" do
        [:welcome, :add, :import, :extension].each do |page|
          div class: "border rounded-xl w-[550px] h-[564px] p-6" do
            send(page)
          end
        end
      end
    end

    def welcome
      div class: "h-full flex flex-center flex-col" do
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
          button class: "text-blue-600" do
            "Skip"
          end
        end
      end
    end

    def add
      div class: "flex gap-4 justify-between items-baseline w-full mb-4" do
        div class: "text-xl font-bold" do
          "Add Content"
        end
        button class: "text-500" do
          "Clear All (2)"
        end
      end
      div class: "grid grid-cols-2 sm:grid-cols-3 gap-4" do
        9.times do
          tile(title: "Daring Fireball", subtitle: "daringfireball.net")
        end
      end
    end

    def extension
      div class: "flex flex-col gap-4" do

        div class: "text-xl font-bold" do
          "Get the Extension"
        end
        image_tag("extension-promo", class: "rounded")
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
          "Choose File"
        end

      end
    end

    def import
      div class: "w-full h-full border rounded-xl border-dashed flex flex-col gap-4 flex-center" do
        Icon("icon-cloud", class: "fill-600")
        div class: "" do
          "Drag & Drop OPML Here"
        end
        div class: "font-bold" do
          "OR"
        end
        button class: "button button-secondary" do
          "Choose File"
        end
      end

    end

    def tile(title:, subtitle:)
      button class: "block rounded-lg border ring-0 border-200 p-3 hover:border-300 transition cursor-pointer text-sm text-left" do
        div class: "aspect-[16/9] bg-200 rounded mb-2"
        div class: "font-medium truncate" do
          title
        end
        div class: "text-500 text-xs truncate" do
          subtitle
        end
      end
    end

    def big_button(title:, subtitle:, icon:)
      button class: "border rounded-xl flex items-center gap-4 p-4 grow" do
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
