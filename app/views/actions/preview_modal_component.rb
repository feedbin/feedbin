module Actions
  class PreviewModalComponent < ApplicationComponent
    def initialize(action:)
      @action = action
    end
    def view_template
      render App::ModalComponent.new(purpose: "action_preview") do |modal|
        modal.title do
          "Action Results"
        end
        modal.body do
          div(class: "action-description") do
            div(class: "content") do
              render partial: "text_description", locals: { action: @action, summary: false }
            end
          end

          p do
            plain helpers.number_to_human(@action.results.total, precision: 2).downcase
            plain " match".pluralize(@action.results.total)
          end

          if @action.results.records.present?
            div(class: "entries action-preview-entries") do
              ul { render partial: "entries/entry", collection: @action.results.records }
            end
          end

          script do
            unsafe_raw(
              <<-JAVASCRIPT
              $('.modal').on('hidden.bs.modal', function (event) {
                $("body > [data-modal-purpose=action_preview]").remove();
              });
              feedbin.localizeTime();
              JAVASCRIPT
            )
          end
        end
      end
    end
  end
end
