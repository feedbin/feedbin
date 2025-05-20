module Dialog
  class NewMute < ApplicationComponent
    TITLE = "Mute Words"

    def view_template
      render Dialog::Template::Wrapper.new(dialog_id: self.class.dom_id) do
        form_with url: mutes_path, data: {remote: true}, method: :post, autocomplete: "off", novalidate: true do |form|
          input type: "hidden", name: "feed_id", data: {behavior: "new_mute_feed_id"}
          render Dialog::Template::InnerContent.new do |dialog|
            dialog.title do
              TITLE
            end

            dialog.body do
              div class: "flex items-center gap-2" do
                div class: "grow" do
                  render Form::TextInputComponent.new do |text|
                    text.input do
                      input name: "query", type: "text", class: "peer text-input", placeholder: "Muted Keyword", id: "mute_keywords", data: {behavior: "auto_submit_throttled"}
                    end
                  end
                end
                div class: "shrink-0" do
                  render Form::SelectInputComponent.new do |input|
                    input.input do
                      select_tag :all_feeds, options_for_select([["All Feeds", "true"], ["This feed only", "false"]]), class: "peer", data: {behavior: "auto_submit"}
                    end
                  end
                end
              end
              div data: {behavior: "new_mute_message_target"} do
                render Message.new(action: nil)
              end
            end

            dialog.footer do
              render Dialog::Template::FooterControls.new do
                a href: mutes_path, class: "dialog-button-secondary", data: {remote: "true", open_dialog: Dialog::ManageMutes.dom_id}  do
                  "Manage Mutes"
                end

                button class: "dialog-button-primary", type: "submit", name: "button_action", value: "save" do
                  "Save"
                end
              end
            end
          end
        end
      end
    end

    class Message < ApplicationComponent
      def initialize(action:)
        @action = action
      end

      def view_template
        div class: "text-500 text-sm pt-2" do
          if @action.present?
            if @action.valid?
              render partial("actions/text_description", action: @action, summary: false )

              plain " Approximately "
              strong { number_to_human(@action.results.total, precision: 2).downcase }
              plain " existing #{"article".pluralize(@action.results.total)} #{@action.results.total == 1 ? "matches" : "match"}."
            else
              plain @action.errors.full_messages.join('. ')
            end
          else
            plain "Mute articles matching these keywords."
          end
        end
      end
    end
  end
end
