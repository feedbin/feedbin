module SourceMenu
  class Tag < ApplicationComponent
    def initialize(tag:, source_target:)
      @tag = tag
      @source_target = source_target
    end

    def view_template
      render(Wrapper.new) do
        render ActionMarkRead.new(source_target: @source_target)
        render ActionEdit.new(href: edit_tag_path(@tag))

        li do
          button data: {behavior: "source_menu_unsubscribe", message: "Are you sure you want to delete this tag?"} do
            span class: "icon-wrap" do
              render SvgComponent.new("menu-icon-delete")
            end
            span class: "menu-text" do
              span class: "title" do
                "Delete"
              end
            end
            form_with url: tag_path(@tag), method: :delete, local: false do |form|
              form.submit type: "submit", class: "ui-helper-hidden-accessible", tabindex: "-1"
            end
          end
        end
      end
    end
  end
end
