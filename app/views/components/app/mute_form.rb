module App
  class MuteForm < ApplicationComponent
    def view_template
      render App::ShareFormComponent.new title: "Create Mute Filter", icon: "icon-block" do
        form_with url: mutes_path, data: {remote: true}, method: :post, autocomplete: "off", novalidate: true do |form|
          input type: "hidden", name: "feed_id"
          div(class: "mb-4") do
            render Form::TextInputComponent.new do |text|
              text.input do
                input name: "query", type: "text", class: "peer text-input", placeholder: "Muted Keyword", id: "mute_keywords"
              end
            end
          end
          div class: "mb-4 flex items-center space-between" do
            render Form::SelectInputComponent.new do |input|
              input.input do
                select_tag(:all_feeds, options_for_select([["All Feeds", "true"], ["This feed only", "false"]]), class: "peer")
              end
            end
            div class: "text-500 ml-auto" do
              "46 existing matches"
            end
          end
          render Settings::ButtonRowComponent.new do
            a href: mutes_path, class: "mr-auto", data: {remote: "true", open_dialog: Dialog::ManageMutes.dom_id}  do
              "Manage Mutes"
            end

            button type: "submit", class: "visually-hidden", tabindex: "-1", name: "preview"

            button type: "button", class: "button button-secondary", data: { behavior: "close_entry_basement" } do
              "Cancel"
            end
            button type: "submit", class: "button" do
              "Save"
            end
          end
        end
      end
    end
  end
end
