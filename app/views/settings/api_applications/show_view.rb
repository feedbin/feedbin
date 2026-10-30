module Settings
  module ApiApplications
    class ShowView < ApplicationView
      def initialize(user:, application:, plaintext_secret: nil, plaintext_token: nil)
        @user = user
        @application = application
        @plaintext_secret = plaintext_secret
        @plaintext_token = plaintext_token
      end

      def view_template
        render Settings::H1Component.new do
          @application.name
        end
        render Settings::SubtitleComponent.new do
          link_to "All applications", settings_api_applications_path
        end

        one_time_secret("Client Secret", @plaintext_secret) if @plaintext_secret.present?
        one_time_secret("Access Token", @plaintext_token) if @plaintext_token.present?

        credentials
        tokens
        advanced
      end

      def one_time_secret(title, value)
        div class: "border border-blue-600 rounded-lg p-4 mb-14" do
          div(class: "text-600 font-bold mb-1") { title }
          div(class: "text-500 text-sm mb-3") { "Copy it now. It is stored hashed, so it won’t be shown again." }
          div class: "font-mono text-sm break-all" do
            render CopyableComponent.new(data: value) { value }
          end
        end
      end

      def credentials
        render Settings::ControlGroupComponent.new class: "mb-14" do |group|
          group.header { "OAuth" }

          group.item do
            render Settings::ControlRowComponent.new do |row|
              row.title { "Client ID" }
              row.description do
                span(class: "font-mono break-all") { render CopyableComponent.new(data: @application.uid) { @application.uid } }
              end
            end
          end

          group.item do
            render Settings::ControlRowComponent.new do |row|
              row.title { "Client Type" }
              row.description do
                if @application.confidential?
                  "Confidential. Authenticate to the token endpoint with the client secret, which was shown once when the app was created."
                else
                  "Public. Authenticate with PKCE (S256); there is no client secret."
                end
              end
            end
          end

          group.item do
            render Settings::ControlRowComponent.new do |row|
              row.title { "Redirect URIs" }
              row.description do
                uris = @application.redirect_uri.to_s.split
                if uris.empty?
                  plain "None. This app can only use tokens created below."
                else
                  uris.each { |uri| div(class: "font-mono break-all") { uri } }
                end
              end
            end
          end

          group.item do
            render Settings::ControlRowComponent.new do |row|
              row.title { "Authorization URL" }
              row.description { span(class: "font-mono break-all") { oauth_authorization_url } }
            end
          end

          group.item do
            render Settings::ControlRowComponent.new do |row|
              row.title { "Token URL" }
              row.description { span(class: "font-mono break-all") { oauth_token_url } }
            end
          end
        end
      end

      def tokens
        tokens = @application.access_tokens.where(resource_owner_id: @user.id, revoked_at: nil).order(created_at: :desc)

        render Settings::ControlGroupComponent.new class: "mb-14" do |group|
          group.header { "Your Tokens" }

          group.item do
            form_with(scope: :token, url: settings_api_application_tokens_path(@application), class: "py-3 flex items-center gap-4") do |form|
              div class: "grow" do
                render Form::TextInputComponent.new do |text|
                  text.input do
                    form.text_field :device_name, placeholder: "Token name, like “curl on my Mac”", class: "peer text-input", autocomplete: "off"
                  end
                end
              end
              button(class: "button button-secondary", type: "submit") { "Create Token" }
            end
          end

          tokens.each do |token|
            group.item do
              render Settings::ControlRowComponent.new do |row|
                row.title { token.device_name.presence || "Unnamed token" }
                row.description do
                  plain "Created #{timeago_text(token.created_at)}"
                  plain(token.last_used_at ? " · Last used #{timeago_text(token.last_used_at)}" : " · Never used")
                end
                row.control do
                  render(Settings::DeleteButtonComponent.new(url: settings_api_application_token_path(@application, token), confirm: "Revoke this token? Clients using it will be signed out.")) { "Revoke" }
                end
              end
            end
          end

          group.description { "Tokens act as your account and don’t expire. Revoke one to sign out the client using it." }
        end
      end

      def advanced
        render Settings::ControlGroupComponent.new class: "mb-14" do |group|
          group.header { "Advanced" }
          group.item do
            render Settings::ControlRowComponent.new do |row|
              row.title { "Delete Application" }
              row.description { "Revokes every token issued to this app, including ones other people granted." }
              row.control do
                render(Settings::DeleteButtonComponent.new(url: settings_api_application_path(@application), confirm: "Delete #{@application.name}? Every token it holds stops working.")) { "Delete" }
              end
            end
          end
        end
      end
    end
  end
end
