module Dialog
  class ExtractedContent < ApplicationComponent
    TITLE = "Extracted Content"

    def initialize(page:, content:)
      @page = page
      @content = content
    end

    def view_template
      helpers.present helpers.current_user do |user_presenter|
        render Dialog::Template::Content.new(dialog_id: self.class.dom_id) do |dialog|
          dialog.title do
            TITLE
          end

          dialog.body do
            div class: "entry-inner animate-fade-in #{user_presenter.display_prefs}" do
              header class: "entry-header" do
                link_to @page.url, target: "_blank", rel: "noopener noreferrer" do
                  h1 { @page.title || "Untitled" }
                end
                if @page.author || @page.published || @page.domain
                  p class: "post-meta" do
                    time { @page.published.to_formatted_s(:full_human) } if @page.published
                    if @page.author
                      plain " by "
                      plain @page.author
                    end
                  end
                  p class: "post-meta" do
                    @page.domain
                  end
                end
              end

              div class: "content-styles entry-type-default pb-1", data_behavior: "view_link_markup_wrap external_links" do
                unsafe_raw @content.html_safe
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
        render Dialog::Template::Content.new(dialog_id: self.class.dom_id) do |dialog|
          dialog.title do
            TITLE
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
  end
end
