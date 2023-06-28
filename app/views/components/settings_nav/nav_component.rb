module SettingsNav
  class NavComponent < ApplicationComponent

    def initialize(title:, subtitle: nil, url:, icon:, selected: false, classes: nil)
      @title = title
      @subtitle = subtitle
      @url = url
      @icon = icon
      @selected = selected
      @classes = classes
    end

    def template(&)
      li(class: %(mb-1 #{@classes})) do
        link_to *[*link_attributes] do
          span(class: "grid place-items-center shrink-0 w-[16px] h-[17px]") do
            render SvgComponent.new(@icon, inline: true, class: "fill-600 group-data-selected:fill-white")
          end
          span do
            span(class: "block leading-[17px] mb-1 group-data-selected:text-white") do
              plain @title
            end
            if @subtitle.present?
              span(class: "block text-sm text-500 group-data-selected:text-white/70 group-data-[nav=dropdown]:text-xs" ) do
                plain @subtitle
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
