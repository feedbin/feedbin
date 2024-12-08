module Shared
  module Modals
    class ViewLinkComponent < ApplicationComponent
      def view_template
        render App::ModalComponent.new(purpose: "view_link", classes: "modal-lg") do |modal|
          modal.title do
            "Extracted Content"
          end
          modal.body do
            render partial: "shared/loading_content_placeholder"
          end
        end
      end
    end
  end
end
