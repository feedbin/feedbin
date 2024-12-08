module Extracts
  class ModalComponent < ApplicationComponent
    def initialize(page:, content:)
      @page = page
      @content = content
    end

    def view_template
      helpers.present helpers.current_user do |user_presenter|
        div class: "modal-wrapper" do
          render App::ModalComponent::ModalInnerComponent.new do |modal|
            modal.title do
              "Extracted Content"
            end

            modal.body do
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
end
