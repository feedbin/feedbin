module SourceMenu
  class ActionMarkRead < ApplicationComponent
    def initialize(source_target:)
      @source_target = source_target
    end

    def view_template
      li do
        button data: {behavior: "menu_mark_read", source_target: @source_target} do
          span class: "icon-wrap" do
            render SvgComponent.new("menu-icon-mark-read")
          end
          span class: "menu-text" do
            span class: "title" do
              "Mark as read"
            end
          end
        end
      end
    end
  end
end
