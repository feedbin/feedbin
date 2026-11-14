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
                row.control do
                  link_to "Manage", settings_api_application_path(application), class: "button button-tertiary"
                end
              end
            end
          end
        end
      end

      # One row per app the user has signed in to, their own apps included.
      # Revoking it signs them out of that app on every device.
      def authorized_applications
        sign_ins = @user.oauth_access_tokens.sign_ins.includes(:application).load
        return if sign_ins.empty?

        apps = sign_ins.group_by(&:application).sort_by { |_, tokens| -tokens.map { it.last_used_at || it.created_at }.max.to_i }

        # Without the image data: only whether there is one, and its version.
        logos = Api::V3::ApplicationLogo.where(application_id: apps.map { |application, _| application.id }).select(:id, :application_id, :updated_at).index_by(&:application_id)

        render Settings::ControlGroupComponent.new class: "mb-14" do |group|
          group.header { "Authorized Apps" }
          apps.each do |application, tokens|
            last_used = tokens.filter_map(&:last_used_at).max
            logo = logos[application.id]
            group.item do
              render Settings::ControlRowComponent.new do |row|
                # Apps without a logo keep the space, so the names line up.
                if logos.any?
                  row.icon do
                    div class: "size-8" do
                      img(src: oauth_application_logo_path(application.uid, v: logo.updated_at.to_i), alt: "#{application.name} logo", class: "size-8 rounded-lg object-contain") if logo
                    end
                  end
                end
                row.title { application.name }
                row.description do
                  plain "Authorized #{timeago_text(tokens.map(&:created_at).min)}"
                  plain " · Last used #{timeago_text(last_used)}" if last_used
                end
                row.control do
                  render(Settings::DeleteButtonComponent.new(url: settings_api_authorization_path(application), confirm: "Revoke access for #{application.name}? It will be signed out on every device.")) { "Revoke" }
                end
              end
            end
          end
          group.description { "Apps that can use your account. Revoking one signs it out everywhere." }
        end
      end
    end
  end
end
