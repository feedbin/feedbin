module SourceMenu
  class ActionEdit < ApplicationComponent
    def initialize(href:)
      @href = href
    end

    def view_template
      li do
        a href: @href, data: {behavior: "close_source_menu", open_dialog: Dialog::EditSubscription.dom_id, remote: true} do
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
