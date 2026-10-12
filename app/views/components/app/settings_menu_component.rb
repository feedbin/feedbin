module App
  class SettingsMenuComponent < ApplicationComponent
    def view_template
      div class: "settings-menu dropdown-content group hide", data_behavior: "menu_content", data_nav: "dropdown" do
        render Shared::SettingsNavView.new(user: current_user)
      end
    end
  end
end
