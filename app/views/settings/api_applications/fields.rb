module Settings
  module ApiApplications
    # The fields an application's new and edit forms share. The client type is
    # only on the new form: clients are built against one or the other.
    module Fields
      def errors
        if @application.errors.any?
          p class: "text-red-600 mb-8" do
            "#{@application.errors.full_messages.join(". ")}."
          end
        end
      end

      # Removal is its own form (#remove_logo), rendered outside this one.
      def logo_field
        logo = Api::V3::ApplicationLogo.for(@application)

        div class: "mb-8" do
          div(class: "mb-2 text-600") { label(for: "logo") { "Logo" } }
          div class: "flex flex-wrap items-center gap-4" do
            if logo
              img src: oauth_application_logo_path(@application.uid, v: logo.updated_at.to_i), alt: "#{@application.name} logo", class: "w-16 h-16 rounded-[14px] object-contain shrink-0"
            end
            input type: "file", name: "logo", id: "logo", accept: "image/png,image/jpeg,image/gif,image/webp", class: "grow basis-[200px] min-w-0 text-sm"
            if logo
              button(type: "submit", form: "remove_logo", class: "button button-secondary", data: {confirm: "Remove the logo?"}) { "Remove" }
            end
          end
          p(class: "text-sm text-500 mt-2") { "Shown above your app’s name when it asks for access. PNG, JPEG, GIF or WebP; square works best." }
        end
      end

      def name_and_redirect_fields(form)
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
      end
    end
  end
end
