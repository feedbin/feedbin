module Shared
  module Modals
    class EditComponent < ApplicationComponent
      def view_template
        render App::ModalComponent.new(purpose: "edit") do |modal|
          modal.body do
            render partial: "shared/modal_placeholder"
          end
        end
      end
    end
  end
end
