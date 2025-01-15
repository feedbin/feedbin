module Shared
  module Modals
    class AddFormComponent < ApplicationComponent
      def view_template
        render App::ModalComponent.new(purpose: "subscribe") do |modal|
          modal.content do
            form_with url: search_feeds_path, class: "feeds-search modal-header-input relative group", data: { behavior: "feeds_search", remote: true }, html: { autocomplete: "off", novalidate: true } do
              label for: "q" do
                "+ Add"
              end

              search_field_tag :q, "", placeholder: "Search or URL", autocomplete: "off", autocorrect: "off", autocapitalize: "off", spellcheck: false, data: { behavior: "feeds_search_field autofocus" }
              span data_behavior: "feeds_search_favicon_target", class: "favicon-target"

              div class: "absolute right-6 inset-y-0" do
                render App::SpinnerComponent.new
              end
            end
          end

          modal.body do
            div data_behavior: "subscribe_target", class: "available-subscriptions"
          end

          modal.footer do
            div(class: "password-footer hide") do
              button type: "button", class: "button button-tertiary", data_dismiss: "modal" do
                "Cancel"
              end
              button type: "button", class: "button", data_behavior: "submit_add" do
                "Continue"
              end
            end

            div class: "subscribe-footer" do
              span data_behavior: "feeds_search_messages", class: "modal-footer-message" do
                span data_behavior: "feeds_search_message message_none", class: "hide" do
                  "Select one or more feeds"
                end
                span data_behavior: "feeds_search_message message_one", class: "hide" do
                  "Subscribe to the selected feed"
                end
                span data_behavior: "feeds_search_message message_multiple", class: "hide" do
                  "Subscribe to the selected feeds"
                end
              end
              button type: "button", class: "button button-tertiary", data_dismiss: "modal" do
                "Cancel"
              end
              button type: "button", class: "button", data_behavior: "submit_add", disabled: "disabled" do
                "Add"
              end
            end
          end
        end
      end
    end
  end
end
