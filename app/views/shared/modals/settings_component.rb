module Shared
  module Modals
    class SettingsComponent < ApplicationComponent
      def view_template
        render App::ModalComponent.new(purpose: "settings_nav", classes: "modal-lg") do |modal|
          modal.title do
            "Settings"
          end
          modal.body do
            div data_nav: "modal", class: "group" do
              render Shared::SettingsNavView.new(user: helpers.current_user)
            end
          end
        end
      end
    end
  end
end
