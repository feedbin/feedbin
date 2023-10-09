module App
  class FeedComponent < ApplicationComponent
    slots :icon, :title, :subhead, :accessory, :content

    def template
      div(class: "flex grow items-start gap-2") do
        div(class: "mt-[2px] shrink-0", &@icon)
        div(class: "flex grow gap-2 space-between items-center") do
          div(class: "grow") do
            div(class: "flex items-baseline justify-between gap-8") do
              h2(&@title)
              if accessory?
                div(class: "text-sm text-500 gap-2 items-center tw-hidden sm:flex", &@accessory)
              end
            end
            p(class: "text-sm", &@subhead)
          end
        end
      end
    end
  end
end