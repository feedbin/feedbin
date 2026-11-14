module Settings
  module ApiApplications
    class ShowView < ApplicationView
      def initialize(user:, application:, profile:, plaintext_token: nil)
        @user = user
        @application = application
        @profile = profile
        @plaintext_token = plaintext_token
      end

      def view_template
        render Settings::H1Component.new do
          "Developers"
        end

        details
        credentials
        tokens
      end

      # What the owner can change, on the edit form. The card is the one
      # Settings::Subscriptions::Shared::FormComponent opens with.
      def details
        uris = @application.redirect_uri.to_s.split

        div class: "border rounded-lg mb-14" do
          div class: "flex items-center gap-3 p-4" do
            if @profile.logo_url
              img src: @profile.logo_url, alt: "#{@application.name} logo", class: "size-8 rounded-lg object-contain shrink-0"
            end
            span(class: "truncate text-lg mr-6") { @application.name }
            link_to "Edit", edit_settings_api_application_path(@application), class: "button button-secondary !ml-auto"
          end
          detail("Description") { plain @profile.description } if @profile.description
          detail("URL") { link_to @profile.url, @profile.url, class: "break-all", rel: "noopener noreferrer" } if @profile.url
          detail("Contact Email") { plain @profile.contact_email } if @profile.contact_email
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

      def detail(title, &block)
        div class: "border-t p-4" do
          div(class: "text-600") { title }
          div(class: "text-500 text-sm", &block)
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

        # Stored hashed, so the value exists only on the request after create.
        created = Doorkeeper::AccessToken.by_token(@plaintext_token) if @plaintext_token.present?

        render Settings::ControlGroupComponent.new class: "mb-14 [&_[data-item-container]]:border-t-0" do |group|
          group.header { "Personal Tokens" }

          group.item do
            form_with(scope: :token, url: settings_api_application_tokens_path(@application), class: "pb-3 flex items-center gap-4") do |form|
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
            group.item(id: "token_#{token.id}") do
              render Settings::ControlRowComponent.new do |row|
                row.title { token.device_name }
                row.description do
                  if token == created
                    div(class: "text-700 my-1") { copyable(@plaintext_token) }
                    plain "Copy it now, it won’t be shown again. It doesn’t expire and can read and change everything in your account, so keep it private."
                  else
                    plain "Created #{timeago_text(token.created_at)}"
                    plain(token.last_used_at ? " · Last used #{timeago_text(token.last_used_at)}" : " · Never used")
                  end
                end
                row.control do
                  render(Settings::DeleteButtonComponent.new(url: settings_api_application_token_path(@application, token), confirm: "Revoke this token? Clients using it will be signed out.")) { "Revoke" }
                end
              end
            end
          end

          group.description do
            plain "A token lets a script, a command-line tool, or the app you’re building use the API as you, without the sign-in step. Send it as "
            code(class: "font-mono") { "Authorization: Bearer <token>" }
            plain "."
          end
        end
      end
    end
  end
end
