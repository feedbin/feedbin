module Settings
  module ApiApplications
    class EditView < ApplicationView
      include Fields

      def initialize(application:, profile:)
        @application = application
        @profile = profile
      end

      def view_template
        form_with(model: @application, url: settings_api_application_path(@application), method: :patch, multipart: true) do |form|
          render Settings::H1Component.new do
            "Edit Application"
          end

          errors
          name_field(form)
          profile_fields
          redirect_field(form)
          logo_field

          render Settings::ButtonRowComponent.new do
            link_to "Cancel", settings_api_application_path(@application), class: "button button-tertiary"
            button(class: "button", type: "submit") { "Save" }
          end
        end

        form_with(url: settings_api_application_logo_path(@application), method: :delete, id: "remove_logo") {}
      end
    end
  end
end
