module Settings
  module ImportItems
    class ImportItemComponent < ApplicationComponent

      def initialize(import_item:)
        @import_item = import_item
      end

      def template
        render App::ExpandableContainerComponent.new(open: true) do |expandable|
          expandable.content do
            div class: "border rounded-lg mb-4 p-4" do
              if helpers.current_user.setting_on?(:fix_feeds_flag) && @import_item.discovered_feeds.present?
                render FixFeeds::SuggestionComponent.new(replaceable: @import_item, source: @import_item, redirect: helpers.fix_feeds_url)
              else
                render App::FeedComponent do |feed|
                  feed.icon do
                    helpers.favicon_with_record(@import_item.favicon, host: @import_item.host, generated: true)
                  end
                  feed.title do
                    link_to @import_item.details[:title] || "Untitled", @import_item.details[:html_url], target: "_blank", class: "!text-600"
                  end
                  feed.subhead do
                    a(href: @import_item.details[:xml_url], class: "!text-500 truncate" ) do
                      helpers.short_url(@import_item.details[:xml_url])
                    end
                  end
                  feed.accessory do
                    span(class: "text-red-600") { @import_item.human_error }
                  end
                end
              end
            end
          end
        end
      end

    end
  end
end