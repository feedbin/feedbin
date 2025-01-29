class Common::FeedsList < ApplicationComponent

  def initialize(feeds:)
    @feeds = feeds
  end

  def view_template
    @feeds.each do |feed|
      render Item.new(feed: feed)
    end
  end

  class Item < ApplicationComponent
    attr_accessor :feed

    def initialize(feed:)
      @feed = feed
    end

    def view_template
      li data: { feed_id: feed.id, behavior: "draggable sort_feed keyboard_navigable", sort_id: feed.id, feed_path: feed_path(feed) } do
        render Common::FeedLink.new(feed: @feed) do
          span class: "link-inner" do
            render FaviconComponent.new(feed: feed)
            span class: "collection-label-wrap", data: { behavior: "rename_target user_title", form_action: feed_rename_path(feed.id), input_name: "feed[title]", title: feed.title, original_title: feed.original_title, feed_id: feed.id } do
              span class: "collection-label", data: { behavior: "user_title rename_title", feed_id: feed.id } do
                feed.title
              end
            end
            span class: "count-wrap" do
              span class: "count", data: { behavior: "needs_count", count_group: "byFeed", count_group_id: feed.id }
              span class: "muted-icon hide" do
                render SvgComponent.new("menu-icon-mute")
              end
            end
            render SourceMenu::Feed.new(feed: feed, source_target: feed.id)
          end
        end
      end
    end
  end
end
