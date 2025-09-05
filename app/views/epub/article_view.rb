module Epub
  class ArticleView < ApplicationComponent
    def initialize(entry:, source:)
      @entry = entry
      @source = source
    end

    def view_template
      html do
        head do
          title { @entry.plain_title_with_default }
          link rel: "stylesheet", type: "text/css", href: "css.css"
        end

        body do
          h1 { @entry.plain_title_with_default }

          p do
            plain @entry.published&.to_formatted_s(:full_human)
            plain " "
            plain @entry.author
            br
            a(href: @entry.fully_qualified_url) { @source }
          end

          raw safe(ContentFormatter.evernote_format(@entry.content, @entry))
        end
      end
    end
  end
end