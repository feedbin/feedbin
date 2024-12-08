module Settings
  class AppearanceComponent < ApplicationComponent
    def view_template
      div(class: "modal-wrapper") do
        helpers.present helpers.current_user do |user_presenter|
          form_for user_presenter, remote: true, url: settings_update_user_path(helpers.current_user) do |form_builder|
            render App::ModalComponent::ModalInnerComponent.new do |modal|
              modal.title do
                "Advanced"
              end

              modal.body do
                render Settings::ControlGroupComponent.new class: "mb-14" do |group|
                  group.header { " Display " }
                  group.item do
                    form_builder.radio_button( :entries_display, "block", { checked: helpers.current_user.entries_display.nil? || helpers.current_user.entries_display === "block", data: { behavior: "appearance_radio auto_submit", setting: "entries-display" }, class: "peer" } )
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
                    form_builder.check_box :entries_feed, { checked: helpers.current_user.entries_feed.nil? || helpers.current_user.setting_on?(:entries_feed), data: { behavior: "appearance_checkbox auto_submit", setting: "entries-feed" }, class: "peer" }
                    form_builder.label :entries_feed, class: "group" do
                      render Settings::ControlRowComponent.new do |row|
                        row.title { "Feed" }
                        row.control { render Form::SwitchComponent.new }
                      end
                    end
                  end
                  group.item do
                    form_builder.check_box :entries_body, { checked: helpers.current_user.entries_body.nil? || helpers.current_user.setting_on?(:entries_body), data: { behavior: "appearance_checkbox auto_submit", setting: "entries-body" }, class: "peer" }
                    form_builder.label :entries_body, class: "group" do
                      render Settings::ControlRowComponent.new do |row|
                        row.title { "Summary" }
                        row.control { render Form::SwitchComponent.new }
                      end
                    end
                  end
                  group.item do
                    form_builder.check_box :entries_image, { checked: helpers.current_user.entries_image.nil? || helpers.current_user.setting_on?(:entries_image), data: { behavior: "appearance_checkbox auto_submit", setting: "entries-image" }, class: "peer" }
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
end
