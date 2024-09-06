module Epub
  class ArticleView < ApplicationComponent
    def initialize(entry:, source:)
      @entry = entry
      @source = source
    end

    def template
      html do
        head do
          title { @entry.title.to_plain_text }
          link rel: "stylesheet", type: "text/css", href: "css.css"
        end

        body(class: "p-4") do
          h1(class: "text-2xl font-bold mb-2") { @entry.title.to_plain_text }

          p(class: "text-gray-600 mb-4") do
            plain @entry.published&.to_formatted_s(:full_human)
            plain " "
            plain @entry.author
            br
            a(href: @entry.fully_qualified_url, class: "text-blue-600 hover:underline") { @source }
          end

          unsafe_raw ContentFormatter.evernote_format(@entry.content, @entry)
        end
      end
    end
  end
end