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
