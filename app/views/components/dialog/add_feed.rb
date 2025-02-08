module Dialog
  class AddFeed < ApplicationComponent
    DIALOG_ID = "add_feed"

    def view_template
      render Dialog::Template::Content.new(dialog_id: DIALOG_ID) do |dialog|
        dialog.title do
          "Add Feed"
        end
        dialog.body do
          form_with url: search_feeds_path, data: { behavior: "feeds_search", remote: true }, html: { autocomplete: "off", novalidate: true } do

            render Form::TextInputComponent.new do |text|

              text.input do
                search_field_tag :q, "", placeholder: "Search or URL", autocomplete: "off", autocorrect: "off", autocapitalize: "off", spellcheck: false, data: { behavior: "feeds_search_field autofocus" }
              end
              text.accessory_leading do
                render SvgComponent.new "favicon-search", class: "ml-2 fill-400 pg-focus:fill-blue-600"
              end

            end


            span data_behavior: "feeds_search_favicon_target", class: "favicon-target"

            div class: "absolute right-6 inset-y-0" do
              render App::SpinnerComponent.new
            end
          end
        end
      end
    end
  end
end

