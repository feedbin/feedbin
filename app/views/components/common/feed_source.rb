class Common::FeedSource < ApplicationComponent
  attr_accessor :feed

  def initialize(feed:)
    @feed = feed
  end

  def view_template
    helpers.present feed do |feed_presenter|
      li data: { feed_id: feed.id, behavior: "draggable sort_feed", sort_id: feed.id, feed_path: feed_path(feed) } do
        feed_presenter.feed_link do
          span(class: "link-inner") do
            feed_presenter.favicon(feed)
            span( class: "collection-label-wrap", data_behavior: "rename_target user_title", data_form_action: feed_rename_path(feed.id), data_input_name: "feed[title]", data_title: feed.title, data_original_title: feed.original_title, data_feed_id: feed.id ) do
              span( class: "collection-label", data_behavior: "user_title rename_title", data_feed_id: feed.id ) do
                feed.title
              end
            end
            span(class: "count-wrap") do
              span class: "count", data: { behavior: "needs_count", count_group: "byFeed", count_group_id: feed.id }
            end
          end
        end
      end
    end
  end
end