module Dialog
  class EditAppearance < ApplicationComponent
    TITLE = "Advanced"

    def view_template
      render Dialog::Template::Content.new(dialog_id: self.class.dom_id) do |dialog|
        dialog.title do
          TITLE
        end

        dialog.body do
          present current_user do |user_presenter|
            form_for user_presenter, remote: true, url: settings_update_user_path(current_user) do |form_builder|
              render Settings::ControlGroupComponent.new class: "mb-14" do |group|
                group.header { " Display " }
                group.item do
                  form_builder.radio_button( :entries_display, "block", { checked: current_user.entries_display.nil? || current_user.entries_display === "block", data: { behavior: "appearance_radio auto_submit", setting: "entries-display" }, class: "peer" } )
                  form_builder.label :entries_display_block, class: "group" do
                    render Settings::ControlRowComponent.new do |row|
                      row.title { "Default" }
                      row.control { render Form::RadioComponent.new }
                    end
                  end
                end
                group.item do
                  form_builder.radio_button( :entries_display, "inline", { data: { behavior: "appearance_radio auto_submit", setting: "entries-display" }, class: "peer" } )
                  form_builder.label :entries_display_inline, class: "group" do
                    render Settings::ControlRowComponent.new do |row|
                      row.title { "Inline" }
                      row.control { render Form::RadioComponent.new }
                    end
                  end
                end
              end
              render Settings::ControlGroupComponent.new do |group|
                group.header { "Interface Elements" }
                group.item do
                  form_builder.check_box :entries_feed, { checked: current_user.entries_feed.nil? || current_user.setting_on?(:entries_feed), data: { behavior: "appearance_checkbox auto_submit", setting: "entries-feed" }, class: "peer" }
                  form_builder.label :entries_feed, class: "group" do
                    render Settings::ControlRowComponent.new do |row|
                      row.title { "Feed" }
                      row.control { render Form::SwitchComponent.new }
                    end
                  end
                end
                group.item do
                  form_builder.check_box :entries_body, { checked: current_user.entries_body.nil? || current_user.setting_on?(:entries_body), data: { behavior: "appearance_checkbox auto_submit", setting: "entries-body" }, class: "peer" }
                  form_builder.label :entries_body, class: "group" do
                    render Settings::ControlRowComponent.new do |row|
                      row.title { "Summary" }
                      row.control { render Form::SwitchComponent.new }
                    end
                  end
                end
                group.item do
                  form_builder.check_box :entries_image, { checked: current_user.entries_image.nil? || current_user.setting_on?(:entries_image), data: { behavior: "appearance_checkbox auto_submit", setting: "entries-image" }, class: "peer" }
                  form_builder.label :entries_image, class: "group" do
                    render Settings::ControlRowComponent.new do |row|
                      row.title { "Media" }
                      row.control { render Form::SwitchComponent.new }
                    end
                  end
                end
              end
            end
          end
        end
      end
    end
  end
end