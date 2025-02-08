module Dialog
  class ExtractedContent < ApplicationComponent
    DIALOG_ID = "extracted_content"

    def initialize(page:, content:)
      @page = page
      @content = content
    end

    def view_template
      helpers.present helpers.current_user do |user_presenter|
        render Dialog::Template::Content.new(dialog_id: DIALOG_ID) do |dialog|
          dialog.title do
            "Extracted Content"
          end

          dialog.body do
            div(class: "entry-inner #{user_presenter.display_prefs}") do
              header(class: "entry-header") do
                link_to @page.url, target: "_blank", rel: "noopener noreferrer" do
                  h1 { @page.title || "Untitled" }
                end
                if @page.author || @page.published || @page.domain
                  p(class: "post-meta") do
                    time { @page.published.to_formatted_s(:full_human) } if @page.published
                    if @page.author
                      plain " by "
                      plain @page.author
                    end
                  end
                  p(class: "post-meta") { plain @page.domain }
                end
              end

              render App::ExpandableContainerComponent.new(auto_open: true) do |expandable|
                expandable.content do
                  div(class: "content-styles entry-type-default", data_behavior: "view_link_markup_wrap external_links") do
                    unsafe_raw @content.html_safe
                  end
                end
              end
            end
          end


        end
      end
    end

    class Error < ApplicationComponent
      def initialize(url:)
        @url = url
      end

      def view_template
        render Dialog::Template::Content.new(dialog_id: DIALOG_ID) do |dialog|
          dialog.title do
            "Extracted Content"
          end

          dialog.body do
            ErrorMessage() do
              "Unable to extract this article’s content."
            end
            p class: "flex justify-end gap-2" do
              a href: @url, class: "button button-secondary", target: "_blank" do
                "Visit Page"
              end
              button(class: "button", data_behavior: "close_dialog") { "Close" }
            end
          end
        end
      end
    end

    class Placeholder < ApplicationComponent
      DIALOG_ID = "extracted_content_placeholder"

      def view_template
        render Dialog::Template::Content.new(dialog_id: DIALOG_ID) do |dialog|
          dialog.title do
            "Extracted Content"
          end
          dialog.body do
            div(class: "entry-inner") do
              p class: "text-center mb-4 text-500" do
                "Loading…"
              end
              div(class: "placeholder-content") do
                7.times do
                  render Line.new
                end
              end
            end
          end
        end
      end

      class Line < Phlex::SVG
        def initialize
          @height = 12
          @duration = "#{3 + rand}s"
        end

        def view_template
          svg(height: @height, width: "100%", ) do |s|
            s.rect(width: "100%", height: @height, class: "[fill:rgb(var(--color-300))]") do
              s.animate(attributename: "opacity", values: "0.4;1;0.4", dur: @duration, repeatcount: "indefinite" )
            end
          end
        end
      end
    end
  end
end
