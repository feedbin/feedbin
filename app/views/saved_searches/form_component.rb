module SavedSearches
  class FormComponent < ApplicationComponent
    def initialize(saved_search:)
      @saved_search = saved_search
    end

    def view_template
      div class: "modal-wrapper" do
        form_for(@saved_search, remote: true, html: { class: "settings", data: { behavior: "disable_on_submit" } } ) do |form_builder|
          render App::ModalComponent::ModalInnerComponent.new do |modal|
            modal.title do
              "Edit Saved Search"
            end

            modal.body do
              div class: "mb-4" do
                render Form::TextInputComponent.new do |text|
                  text.label do
                    form_builder.label :name, "Name"
                  end
                  text.input do
                    form_builder.text_field :name, placeholder: @saved_search.name || "Name"
                  end
                end
              end

              render Form::TextInputComponent.new do |text|
                text.label do
                  form_builder.label :query, "Query"
                end
                text.input do
                  form_builder.text_field :query, placeholder: @saved_search.query, class: "peer text-input"
                end
              end
            end

            modal.footer do
              if @saved_search.persisted?
                link_to saved_search_path(@saved_search), method: :delete, remote: true, class: "button-text delete-button text-sm", data: { confirm: "Are you sure you want to delete this saved search?" } do
                  render SvgComponent.new("icon-delete")
                  plain " Delete"
                end
              end
              button(type: "button", class: "button button-secondary", data_dismiss: "modal", aria_label: "Cancel" ) do
                "Cancel"
              end
              button(type: "submit", class: "button") do
                "Save"
              end
            end
          end
        end
      end
    end
  end
end
