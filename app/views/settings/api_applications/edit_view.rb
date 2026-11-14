module Settings
  module ApiApplications
    class EditView < ApplicationView
      include Fields

      def initialize(application:)
        @application = application
      end

      def view_template
        form_with(model: @application, url: settings_api_application_path(@application), method: :patch) do |form|
          render Settings::H1Component.new do
            "Edit Application"
          end

          errors
          name_and_redirect_fields(form)

          render Settings::ButtonRowComponent.new do
            link_to "Cancel", settings_api_application_path(@application), class: "button button-tertiary"
            button(class: "button", type: "submit") { "Save" }
          end
        end
      end
    end
  end
end
