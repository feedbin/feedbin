module Settings
  module ApiApplications
    class IndexView < ApplicationView
      def initialize(user:)
        @user = user
      end

      def view_template
        render Settings::H1Component.new do
          "API"
        end

        p class: "text-500 mb-8" do
          "Register an app to use the Feedbin API. Apps can ask other Feedbin users for access with OAuth, or you can create a token for your own account and paste it into a client or script."
        end

        applications
      end

      def applications
        render Settings::ControlGroupComponent.new class: "mb-14" do |group|
          group.custom_header do
            div class: "flex items-center mb-4" do
              div class: "grow" do
                render H2Component.new(class: "!mb-0") do
                  "Applications"
                end
              end
              link_to "New Application", new_settings_api_application_path, class: "button button-secondary"
            end
          end

          applications = @user.oauth_applications.order(created_at: :asc).load

          if applications.empty?
            group.item do
              render Settings::ControlRowComponent.new do |row|
                row.title { "No applications yet" }
                row.description { "Create one to get a client ID or a token." }
              end
            end
          end

          applications.each do |application|
            group.item do
              render Settings::ControlRowComponent.new do |row|
                row.title { application.name }
                row.control do
                  link_to "Manage", settings_api_application_path(application), class: "button button-tertiary"
                end
              end
            end
          end
        end
      end
    end
  end
end
