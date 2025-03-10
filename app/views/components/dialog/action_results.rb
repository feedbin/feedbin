module Dialog
  class ActionResults < ApplicationComponent
    TITLE = "Action Results"

    def initialize(action:)
      @action = action
    end

    def view_template
      render Dialog::Template::Content.new(dialog_id: self.class.dom_id) do |dialog|
        dialog.title do
          TITLE
        end
        dialog.body do
          div(class: "action-description") do
            div(class: "content") do
              render partial("text_description", action: @action, summary: false )
            end
          end

          p do
            plain number_to_human(@action.results.total, precision: 2).downcase
            plain " match".pluralize(@action.results.total)
          end

          if @action.results.records.present?
            div(class: "entries action-preview-entries") do
              ul do
                @action.results.records.each do |entry|
                  render partial("entries/entry", entry: entry)
                end
              end
            end
          end
        end
      end
    end

    class Error < ApplicationComponent
      TITLE = "Action Results"

      def initialize(action:)
        @action = action
      end

      def view_template
        render Dialog::Template::Content.new(dialog_id: self.class.dom_id) do |dialog|
          dialog.title do
            TITLE
          end

          dialog.body do
            ErrorMessage() do
              "Invalid Action: #{@action.errors.full_messages.join('. ')}"
            end
          end
        end
      end
    end
  end
end
