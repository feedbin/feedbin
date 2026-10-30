module Settings
  module ApiApplications
    class NewView < ApplicationView
      def initialize(application:)
        @application = application
      end

      def view_template
        form_with(model: @application, url: settings_api_applications_path) do |form|
          render Settings::H1Component.new do
            "New Application"
          end

          if @application.errors.any?
            p class: "text-red-600 mb-8" do
              "#{@application.errors.full_messages.join(". ")}."
            end
          end

          div class: "mb-8" do
            render Form::TextInputComponent.new do |text|
              text.label_content { form.label :name, "Name" }
              text.input do
                form.text_field :name, placeholder: "My Feed Reader", class: "peer text-input", autocomplete: "off"
              end
            end
            p(class: "text-sm text-500 mt-2") { "Shown to people when your app asks for access." }
          end

          div class: "mb-8" do
            render Form::TextInputComponent.new do |text|
              text.label_content { form.label :redirect_uri, "Redirect URIs" }
              text.input do
                form.text_area :redirect_uri, rows: 3, placeholder: "myreader://oauth/callback", class: "peer text-input py-2 h-auto", autocomplete: "off", autocorrect: "off", autocapitalize: "off", spellcheck: "false"
              end
            end
            p(class: "text-sm text-500 mt-2") { "One per line. Leave blank if you only need tokens for your own account." }
          end

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
