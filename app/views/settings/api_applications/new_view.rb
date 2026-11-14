module Settings
  module ApiApplications
    class NewView < ApplicationView
      include Fields

      def initialize(application:)
        @application = application
      end

      def view_template
        form_with(model: @application, url: settings_api_applications_path) do |form|
          render Settings::H1Component.new do
            "New Application"
          end

          errors
          name_and_redirect_fields(form)

          render Settings::ControlGroupComponent.new class: "mb-8" do |group|
            group.item do
              form.check_box :confidential, class: "peer"
              form.label :confidential, class: "group" do
                render Settings::ControlRowComponent.new do |row|
                  row.title { "Confidential" }
                  row.description { "Turn on for apps with a server that can keep a client secret. Leave off for native and browser apps, which use PKCE instead." }
                  row.control { render Form::SwitchComponent.new }
                end
              end
            end
          end

          render Settings::ButtonRowComponent.new do
            link_to "Cancel", settings_api_applications_path, class: "button button-tertiary"
            button(class: "button", type: "submit") { "Create" }
          end
        end
      end
    end
  end
end
