module SourceMenu
  class Wrapper < ApplicationComponent
    def view_template
      button class: "feed-action-button source-menu", data: { behavior: "feed_action toggle_source_menu" } do
        render SvgComponent.new("icon-dots")

        template_tag do
          ul class: "nav" do
            yield
          end
        end
      end
    end
  end
end
