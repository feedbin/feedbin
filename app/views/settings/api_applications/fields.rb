module Settings
  module ApiApplications
    # The fields an application's new and edit forms share.
    module Fields
      def errors
        messages = @application.errors.full_messages + @profile.errors.full_messages
        if messages.any?
          p class: "text-red-600 mb-8" do
            "#{messages.join(". ")}."
          end
        end
      end

      # Removal is its own form (#remove_logo), which the edit view renders
      # outside this one.
      def logo_field
        # The stored logo: an upload that was not saved has nothing to show.
        logo = @profile.persisted? && @profile.logo_updated_at_in_database

        div class: "mb-8" do
          div(class: "mb-2 text-600") { label(for: "profile_logo_file") { "Logo" } }
          div class: "flex flex-wrap items-center gap-4" do
            if logo
              img src: oauth_application_logo_path(@application.uid, v: logo.to_i), alt: "#{@application.name} logo", class: "w-16 h-16 rounded-[14px] object-contain shrink-0"
            end
            input type: "file", name: "profile[logo_file]", id: "profile_logo_file", accept: "image/png,image/jpeg,image/gif,image/webp", class: "grow basis-[200px] min-w-0 text-sm"
            if logo
              button(type: "submit", form: "remove_logo", class: "button button-secondary", data: {confirm: "Remove the logo?"}) { "Remove" }
            end
          end
          p(class: "text-sm text-500 mt-2") { "Shown above your app’s name when it asks for access. PNG, JPEG, GIF or WebP; square works best." }
        end
      end

      def name_field(form)
        div class: "mb-8" do
          render Form::TextInputComponent.new do |text|
            text.label_content { form.label :name, "Name" }
            text.input do
              form.text_field :name, placeholder: "My Feed Reader", class: "peer text-input", autocomplete: "off"
            end
          end
          p(class: "text-sm text-500 mt-2") { "Shown to people when your app asks for access." }
        end
      end

      # The profile's own fields, sent as profile[...] beside the application's.
      def profile_fields
        fields_for :profile, @profile do |form|
          div class: "mb-8" do
            render Form::TextInputComponent.new do |text|
              text.label_content { form.label :description, "Description" }
              text.input do
                form.text_area :description, rows: 3, maxlength: 500, class: "peer text-input py-2 h-auto"
              end
            end
            p(class: "text-sm text-500 mt-2") { "What your app does, in a sentence or two." }
          end

          div class: "mb-8" do
            render Form::TextInputComponent.new do |text|
              text.label_content { form.label :url, "URL" }
              text.input do
                form.url_field :url, placeholder: "https://example.com", class: "peer text-input", autocomplete: "off", autocapitalize: "off", spellcheck: "false"
              end
            end
            p(class: "text-sm text-500 mt-2") { "Your app’s website." }
          end

          div class: "mb-8" do
            render Form::TextInputComponent.new do |text|
              text.label_content { form.label :contact_email, "Contact Email" }
              text.input do
                form.email_field :contact_email, placeholder: "you@example.com", class: "peer text-input", autocomplete: "off", autocapitalize: "off", spellcheck: "false"
              end
            end
            p(class: "text-sm text-500 mt-2") { "Where Feedbin can reach you about this app." }
          end
        end
      end

      def redirect_field(form)
        div class: "mb-8" do
          render Form::TextInputComponent.new do |text|
            text.label_content { form.label :redirect_uri, "Redirect URIs" }
            text.input do
              form.text_area :redirect_uri, rows: 3, placeholder: "myreader://oauth/callback", class: "peer text-input py-2 h-auto", autocomplete: "off", autocorrect: "off", autocapitalize: "off", spellcheck: "false"
            end
          end
          p(class: "text-sm text-500 mt-2") { "One per line. Leave blank if you only need tokens for your own account." }
        end
      end
    end
  end
end
