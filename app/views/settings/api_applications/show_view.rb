module Settings
  module ApiApplications
    class ShowView < ApplicationView
      def initialize(user:, application:, plaintext_token: nil)
        @user = user
        @application = application
        @plaintext_token = plaintext_token
      end

      def view_template
        render Settings::H1Component.new do
          "API"
        end

        one_time_secret("Access Token", @plaintext_token) if @plaintext_token.present?

        details
        credentials
        tokens
      end

      def one_time_secret(title, value)
        div class: "border border-blue-600 rounded-lg p-4 mb-14" do
          div(class: "text-600 font-bold mb-1") { title }
          div(class: "text-500 text-sm mb-3") { "Copy it now. It is stored hashed, so it won’t be shown again." }
          div(class: "text-sm") { copyable(value) }
        end
      end

      # What the owner can change, on the edit form. The card is the one
      # Settings::Subscriptions::Shared::FormComponent opens with.
      def details
        logo = Api::V3::ApplicationLogo.for(@application)
        uris = @application.redirect_uri.to_s.split

        div class: "border rounded-lg mb-14" do
          div class: "flex items-center gap-3 p-4" do
            if logo
              img src: oauth_application_logo_path(@application.uid, v: logo.updated_at.to_i), alt: "#{@application.name} logo", class: "size-8 rounded-lg object-contain shrink-0"
            end
            span(class: "truncate text-lg mr-6") { @application.name }
            link_to "Edit", edit_settings_api_application_path(@application), class: "button button-secondary !ml-auto"
          end
          div class: "border-t p-4" do
            div(class: "text-600") { "Redirect URIs" }
            div class: "text-500 text-sm" do
              if uris.empty?
                plain "None. This app can only use tokens created below."
              else
                uris.each { |uri| copyable(uri) }
              end
            end
          end
        end
      end

      # Fixed when the application was created.
      def credentials
        render Settings::ControlGroupComponent.new class: "mb-14" do |group|
          group.header { "OAuth" }

          group.item do
            render Settings::ControlRowComponent.new do |row|
              row.title { "Client ID" }
              row.description { copyable(@application.uid) }
            end
          end

          group.item do
            render Settings::ControlRowComponent.new do |row|
              row.title { "Authorization URL" }
              row.description { copyable(oauth_authorization_url) }
            end
          end

          group.item do
            render Settings::ControlRowComponent.new do |row|
              row.title { "Token URL" }
              row.description { copyable(oauth_token_url) }
            end
          end
        end
      end

      def copyable(value)
        div class: "font-mono break-all [&_button]:text-left" do
          render CopyableComponent.new(data: value) { value }
        end
      end

      def tokens
        # Tokens from signing in are listed under Authorized Apps.
        tokens = @application.access_tokens.where(resource_owner_id: @user.id, revoked_at: nil).where.not(device_name: nil).order(created_at: :desc)

        render Settings::ControlGroupComponent.new class: "mb-14" do |group|
          group.custom_header do
            render H2Component.new(class: "!mb-1") { "Your Tokens" }
            p class: "text-sm text-500 mb-4" do
              plain "A token lets a script, a command-line tool, or the app you’re building use the API as you, without the sign-in step. Send it as "
              code(class: "font-mono") { "Authorization: Bearer <token>" }
              plain "."
            end
          end

          group.item do
            form_with(scope: :token, url: settings_api_application_tokens_path(@application), class: "py-3 flex items-center gap-4") do |form|
              div class: "grow" do
                render Form::TextInputComponent.new do |text|
                  text.input do
                    form.text_field :device_name, placeholder: "Token name, like “curl on my Mac”", class: "peer text-input", autocomplete: "off", required: true
                  end
                end
              end
              button(class: "button button-secondary", type: "submit") { "Create Token" }
            end
          end

          tokens.each do |token|
            group.item do
              render Settings::ControlRowComponent.new do |row|
                row.title { token.device_name }
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

          group.description { "A token is shown once when you create it, doesn’t expire, and can read and change everything in your account, so keep it private. Revoke it to cut off whatever is using it." }
        end
      end
    end
  end
end
