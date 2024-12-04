module App
  class ModalComponent < ApplicationComponent
    def initialize(purpose:, classes: nil)
      @purpose = purpose
      @classes = classes
    end

    def view_template(&block)
      div class: "hide", data: {behavior: "modal_content", purpose: @purpose} do
        div class: class_names("modal-dialog", @classes), role: "document" do
          render ModalInnerComponent.new(&block)
        end
      end
    end

    class ModalInnerComponent < ApplicationComponent
      slots :content, :title, :body, :footer

      def view_template
        div class: "modal-content" do
          if content?
            yield_content &@content
          end

          if title?
            div class: "modal-header" do
              h5 class: "modal-title" do
                yield_content &@title
              end
              button type: "button", class: "close", data: {dismiss: "modal"}, aria_label: "Close" do
                render SvgComponent.new "icon-close-small"
              end
            end
          end

          if body?
            div class: "modal-body" do
              yield_content &@body
            end
          end

          div class: tokens("modal-footer", -> { !footer? } => "hide") do
            yield_content &@footer if footer?
          end
        end
      end
    end
  end
end