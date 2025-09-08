module SettingsNav
  class NavComponent < ApplicationComponent

    def initialize(title:, subtitle: nil, url:, icon:, selected: false, classes: nil, notification: false)
      @title = title
      @subtitle = subtitle
      @url = url
      @icon = icon
      @selected = selected
      @classes = classes
      @notification = notification
    end

    def view_template(&)
      li(class: %(mb-1 #{@classes})) do
        link_to *[*link_attributes] do
          span(class: "grid place-items-center shrink-0 w-[16px] h-[17px]") do
            Icon(@icon, inline: true, class: "fill-500 group-data-selected:fill-white")
          end
          span do
            span(class: "flex gap-1 leading-[17px] mb-1 group-data-selected:text-white") do
              span  { @title }
              if @notification
                span class: "block rounded-full h-[8px] w-[8px] bg-red-600 group-data-selected:bg-white"
              end
            end
            if @subtitle.present?
              span(class: "block text-sm text-500 group-data-selected:text-white/70 group-data-[nav=dropdown]:text-xs" ) do
                @subtitle
              end
            end
          end
        end
      end
    end

    private

    def link_attributes
      defaults = {
        class: "flex gap-2 p-2 rounded group !text-600 hover:no-underline hover:bg-200 data-selected:bg-blue-600",
        data: {}
      }
      defaults[:data] = { ui: "selected" } if @selected

      link_args = [*@url]
      if link_args.length == 2
        defaults = mix(defaults, link_args.last)
      end
      link_args[1] = defaults
      link_args
    end
  end
end
