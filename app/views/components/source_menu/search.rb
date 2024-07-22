module SourceMenu
  class Search < ApplicationComponent
    def initialize(saved_search:, source_target:)
      @saved_search = saved_search
      @source_target = source_target
    end

    def view_template
      render(Wrapper.new) do
        render ActionMarkRead.new(source_target: @source_target)
        render ActionEdit.new(href: helpers.edit_saved_search_path(@saved_search))

        li do
          button data: {behavior: "source_menu_unsubscribe", message: "Are you sure you want to delete this saved search?"} do
            span class: "icon-wrap" do
              render SvgComponent.new("menu-icon-delete")
            end
            span class: "menu-text" do
              span class: "title" do
                "Delete"
              end
            end
            form_with url: helpers.saved_search_path(@saved_search), method: :delete, data: {remote: true} do |form|
              form.submit type: "submit", class: "ui-helper-hidden-accessible", tabindex: "-1"
            end
          end
        end
      end
    end
  end
end
