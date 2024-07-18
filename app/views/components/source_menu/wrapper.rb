module SourceMenu
  class Wrapper < ApplicationComponent
    def view_template
      form( class: "feed-action-form source-menu-form", data_behavior: "feed_action_parent null_form", data_remote: "true" ) do
        button( type: "submit", class: "feed-action-button source-menu", data_behavior: "feed_action toggle_source_menu" ) do
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
end
