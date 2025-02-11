module Dialog

  class EditSavedSearch < ApplicationComponent
    TITLE = "Edit Saved Search"

    def initialize(saved_search:)
      @saved_search = saved_search
    end

    def view_template
      render SavedSearchForm.new(saved_search: @saved_search, title: TITLE, dialog_id: self.class.dom_id)
    end
  end

  class NewSavedSearch < ApplicationComponent
    TITLE = "New Saved Search"

    def initialize(saved_search:)
      @saved_search = saved_search
    end

    def view_template
      render SavedSearchForm.new(saved_search: @saved_search, title: TITLE, dialog_id: self.class.dom_id)
    end
  end

  class SavedSearchForm < ApplicationComponent

    def initialize(saved_search:, title:, dialog_id:)
      @saved_search = saved_search
      @title = title
      @dialog_id = dialog_id
    end

    def view_template
      render Dialog::Template::Content.new(dialog_id: @dialog_id) do |dialog|
        dialog.title do
          @title
        end
        dialog.body do
          div class: "animate-fade-in" do
            form_for(@saved_search, remote: true, method: @saved_search.persisted? ? :patch : :post, html: {data: {behavior: "close_dialog_on_submit"}}) do |form_builder|
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
          end
          dialog.footer do
            div class: "flex items-center" do
              if @saved_search.persisted?
                link_to saved_search_path(@saved_search), method: :delete, remote: true, class: "!text-600 button-text text-sm flex items-center gap-2", data: { behavior: "close_dialog",confirm: "Are you sure you want to delete this search?" } do
                  render SvgComponent.new("icon-delete", class: "fill-600")
                  plain " Delete"
                end
              end

              button type: "submit", class: "button ml-auto", value: "save", form: helpers.dom_id(@saved_search, @saved_search.persisted? ? :edit : :new) do
                "Save"
              end
            end
          end
        end
      end
    end
  end
end