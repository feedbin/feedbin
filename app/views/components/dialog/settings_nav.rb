module Dialog
  class SettingsNav < ApplicationComponent
    TITLE = "Settings"

    def view_template
      render Dialog::Template::Content.new(dialog_id: self.class.dom_id) do |dialog|
        dialog.title do
          "Settings"
        end
        dialog.body do
          div data_nav: "modal", class: "group" do
            render Shared::SettingsNavView.new(user: helpers.current_user)
          end
        end
      end
    end
  end
end