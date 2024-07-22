module SourceMenu
  class ActionEdit < ApplicationComponent
    def initialize(href:)
      @href = href
    end

    def view_template
      li do
        a href: @href, data: {behavior: "open_settings_modal feed_settings close_source_menu", remote: true} do
          span class: "icon-wrap" do
            render SvgComponent.new("menu-icon-edit")
          end
          span class: "menu-text" do
            span class: "title" do
              "Edit"
            end
          end
        end
      end
    end
  end
end
