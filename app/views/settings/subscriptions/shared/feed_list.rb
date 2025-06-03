module Settings
  module Subscriptions
    module Shared
      class FeedList < ApplicationComponent

        def initialize(feeds:)
          @feeds = feeds
        end

        def view_template
          div data_behavior: "subscriptions_source_list", class: "grid grid-cols-1 md:grid-cols-2 gap-4" do
            @feeds.each do |feed|
              render FeedListItemComponent.new(feed: feed)
            end
          end
        end

      end
    end
  end
end