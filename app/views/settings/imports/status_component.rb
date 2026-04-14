module Settings
  module Imports
    class StatusComponent < ApplicationComponent

      def initialize(import:, onboarding: false)
        @import = import
        @onboarding = onboarding

        @failed_items = @import
          .import_items
          .failed
          .includes(:discovered_feeds, :favicon)
          .sort_by { _1.title }

        @fixable_items = @import
          .import_items
          .fixable
          .includes(:discovered_feeds, :favicon)
          .sort_by { _1.title }
      end

      def view_template
        render Settings::ControlGroupComponent.new class: "group mb-8", data: { capsule: "true" } do |group|
          group.item do
            div(class: "py-3 px-4") do
              div class: "border-b py-3 mb-3" do
                div(class: "flex justify-between") do
                  strong(class: "font-bold") { "Progress" }
                end
                div(class: "flex mt-4 mb-2 bg-100 rounded-full w-full overflow-hidden") do
                  bar_segment(
                    title: "#{number_with_delimiter(@import.import_items.complete.count)} imported",
                    percent_complete: @import.percentage,
                    color_class: "bg-green-600"
                  )
                end
                div(class: "flex justify-between gap-4") do
                  div(class: "text-500 truncate") { plain @import.filename }
                  span(class: "text-500 flex gap-2 items-center") do
                    if @import.percentage == 100
                      Icon("icon-check", class: "fill-green-600")
                    end
                    span do
                      number_to_percentage(@import.percentage.floor, precision: 0)
                    end
                  end
                end
              end

              if @import.complete?
                if @failed_items.present? || @fixable_items.present?
                  details(class: "group flex flex-col") do
                    summary(class: "flex cursor-pointer items-center text-blue-600 gap-2 list-none [&::-webkit-details-marker]:hidden") do
                      Icon("icon-caret", class: "transition -rotate-90 group-open:rotate-0 fill-blue-600")
                      span class: "group-open:tw-hidden" do
                        "View Report"
                      end
                      span class: "tw-hidden group-open:inline" do
                        "Hide Report"
                      end
                    end

                    div(class: "mt-2 w-full") do
                      tabs
                    end
                  end
                else
                  span class: "text-700" do
                    "Import complete"
                  end
                end
              else
                div class: "flex items-center gap-2" do
                  div class: "spinner"
                  span class: "text-700" do
                    "Import in progress"
                  end
                  span class: "text-500" do
                    "- A report will be available upon completion"
                  end
                end
              end
            end
          end
        end

      end

      def tabs
        if @fixable_items.present? && @failed_items.present?
          render TabsComponent.new do |tabs|
            if @fixable_items.present?
              tabs.tab(title: "Fixable") do
                fixable
              end
            end
            if @failed_items.present?
              tabs.tab(title: "Missing") do
                missing
              end
            end
          end
        elsif @fixable_items.present?
          fixable
        elsif @failed_items.present?
          missing
        end
      end

      def missing
        div do
          h2(class: "text-700 font-bold") do
            "Missing Feeds"
          end
          p(class: "text-sm text-500 mb-8") do
            plain number_with_delimiter(@failed_items.count)
            plain " broken"
            plain " link".pluralize(@failed_items.count)
          end

          @failed_items.each_with_index do |import_item, index|
            render ImportItems::ImportItemComponent.new(import_item: import_item, index: index)
          end
        end
      end

      def fixable
        div do
          render FixFeeds::StatusComponent.new(count: @fixable_items.count, replace_path: replace_all_settings_import_path(@import), remote: @onboarding)

          p class: "text-500 mb-8 -mt-4" do
            "Feedbin was unable to import these feeds. However, it looks like there may be working alternatives available."
          end

          @fixable_items.each_with_index do |import_item, index|
            render ImportItems::ImportItemComponent.new(import_item: import_item, index: index)
          end
        end
      end

      def bar_segment(title:, percent_complete:, color_class:)
        div(
          class: "h-[12px] #{color_class}",
          style: "width: #{number_to_percentage(percent_complete)};",
          title: "#{title}",
          data: { toggle: "tooltip" }
        )
      end
    end
  end
end