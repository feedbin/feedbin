module Shared
  module Modals
    class GenericComponent < ApplicationComponent
      def view_template
        render App::ModalComponent.new(purpose: "generic", classes: "modal-md") do |modal|
          modal.title do
            "Title"
          end
          modal.body do
            render partial: "shared/loading_content_placeholder"
          end
        end
      end
    end
  end
end
