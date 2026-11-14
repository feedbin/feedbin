module Settings
  module ApiApplications
    class NewView < ApplicationView
      include Fields

      def initialize(application:)
        @application = application
      end

      def view_template
        form_with(model: @application, url: settings_api_applications_path, multipart: true) do |form|
          render Settings::H1Component.new do
            "New Application"
          end

          errors
          name_and_redirect_fields(form)
          logo_field

          render Settings::ButtonRowComponent.new do
            link_to "Cancel", settings_api_applications_path, class: "button button-tertiary"
            button(class: "button", type: "submit") { "Create" }
          end
        end
      end
    end
  end
end
