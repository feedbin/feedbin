module Settings
  # One row per app the user has signed in to, their own apps included.
  # Revoking it signs them out of that app on every device.
  class AuthorizedAppsComponent < ApplicationComponent
    def initialize(user:)
      @user = user
    end

    def view_template
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
