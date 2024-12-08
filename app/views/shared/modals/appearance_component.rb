module Shared
  module Modals
    class AppearanceComponent < ApplicationComponent
      def view_template
        render App::ModalComponent.new(purpose: "appearance") do |modal|
          modal.body do
            render partial: "shared/modal_placeholder"
          end
        end
      end
    end
  end
end
