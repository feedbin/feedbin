module App
  class TagFieldsComponent < ApplicationComponent
    def initialize(tag_editor:)
      @tag_editor = tag_editor
    end

    def view_template
      label(class: "flex text-input-next items-center gap-2 group items-stretch cursor-text") do
        input(
          placeholder: "+ New Tag",
          type: "text",
          name: "tag_name[]",
          class: "placeholder:font-bold cursor-pointer placeholder:text-center placeholder:!text-700 placeholder:focus:!text-500 focus:placeholder:text-left focus:placeholder:font-normal"
        )
      end

      div class: "#{@tag_editor.tags.present? ? "mt-6" : ""}" do
        @tag_editor.tags.each do |tag|
          div do
            check_box_tag("tag_id[#{tag.id}]", tag.name, checked: @tag_editor.checked?(tag), class: "peer")
            label_tag "tag_id[#{tag.id}]", class: "cursor-pointer group block flex items-center border rounded-lg mt-2 py-3 px-4 gap-3 select-none transition-[border,box_shadow,background] duration-200 peer-checked:border-700 peer-checked:shadow-selected-700 pointer-fine:hover:bg-100" do
              div class: "shrink-0" do
                render Form::CheckboxComponent.new
              end
              div class: "grow truncate min-w-0 pr-2" do
                tag.name
              end
              div class: "shrink-0" do
                render SvgComponent.new("favicon-tag", class: "fill-400")
              end
            end
          end
        end
      end
    end
  end
end
