module Shared
  module Modals
    class ConversationComponent < ApplicationComponent
      def view_template
        render App::ModalComponent.new(purpose: "conversation") do |modal|
          modal.title do
            "Thread"
          end
          modal.body do
            render partial: "shared/loading_content_placeholder"
          end
        end
      end
    end
  end
end
