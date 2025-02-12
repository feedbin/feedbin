module Dialog
  class EditTag < ApplicationComponent
    TITLE = "Edit Tag"

    def initialize(tag:)
      @tag = tag
    end

    def view_template
      render Dialog::Template::Content.new(dialog_id: self.class.dom_id) do |dialog|
        dialog.title do
          TITLE
        end
        dialog.body do
          div class: "animate-fade-in" do
            form_for(@tag, remote: true, method: :patch, html: {data: {behavior: "close_dialog_on_submit"}}) do |form_builder|
              render Form::TextInputComponent.new do |text|
                text.input do
                  form_builder.text_field :name, placeholder: @tag.name
                end
              end
            end
          end
          dialog.footer do
            div class: "flex items-center animate-fade-in" do
              link_to tag_path(@tag), method: :delete, remote: true, class: "!text-600 button-text text-sm flex items-center gap-2", data: { behavior: "close_dialog", confirm: "Are you sure you want to delete this tag?" } do
                render SvgComponent.new("icon-delete", class: "fill-600")
                plain " Delete"
              end

              button type: "submit", class: "button ml-auto", value: "save", form: helpers.dom_id(@tag, :edit) do
                "Save"
              end
            end
          end
        end
      end
    end
  end
end