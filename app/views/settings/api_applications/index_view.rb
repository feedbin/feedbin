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
        authorized_applications
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
                row.description { application.confidential? ? "Confidential" : "Public" }
                row.control do
                  link_to "Manage", settings_api_application_path(application), class: "button button-tertiary"
                end
              end
            end
          end
        end
      end

      # Tokens the user granted to other people's apps through OAuth.
      def authorized_applications
        tokens = @user.oauth_access_tokens
          .where(revoked_at: nil)
          .where.not(application_id: @user.oauth_applications.select(:id))
          .includes(:application)
          .order(created_at: :desc)
          .load

        return if tokens.empty?

        render Settings::ControlGroupComponent.new class: "mb-14" do |group|
          group.header { "Authorized Apps" }
          tokens.each do |token|
            group.item do
              render Settings::ControlRowComponent.new do |row|
                row.title { token.application.name }
                row.description do
                  plain "Authorized #{timeago_text(token.created_at)}"
                  plain " · Last used #{timeago_text(token.last_used_at)}" if token.last_used_at
                end
                row.control do
                  render(Settings::DeleteButtonComponent.new(url: settings_api_application_token_path(token.application_id, token), confirm: "Revoke access for #{token.application.name}?")) { "Revoke" }
                end
              end
            end
          end
        end
      end
    end
  end
end
