module Tags
  class FormComponent < ApplicationComponent
    def initialize(tag:)
      @tag = tag
    end

    def view_template
      div class: "modal-wrapper" do
        form_for(@tag, remote: true, method: :patch, html: { class: "settings tags-form", data: { behavior: "disable_on_submit" } } ) do |form_builder|
          render App::ModalComponent::ModalInnerComponent.new do |modal|
            modal.title do
              "Edit Tag"
            end

            modal.body do
              render Form::TextInputComponent.new do |text|
                text.label do
                  form_builder.label :name, "Name"
                end
                text.input do
                  form_builder.text_field :name, placeholder: @tag.name
                end
              end
            end

            modal.footer do
              link_to tag_path(@tag), method: :delete, remote: true, class: "button-text delete-button text-sm", data: { confirm: "Are you sure you want to delete this tag?" } do
                render SvgComponent.new("icon-delete")
                plain " Delete"
              end
              button( type: "button", class: "button button-secondary", data_dismiss: "modal", aria_label: "Cancel" ) { "Cancel" }
              button(type: "submit", class: "button") { "Save" }
            end
          end
        end
      end
    end
  end
end
