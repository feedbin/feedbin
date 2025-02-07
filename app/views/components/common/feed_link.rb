class Common::FeedLink < ApplicationComponent

  def initialize(feed:, link: nil, behavior: nil)
    @feed = feed
    @link = link
    @behavior = behavior
  end

  def view_template
    a **options do
      yield
    end
  end

  def options
    {
      href: @link || feed_entries_path(@feed),
      class: "feed-link",
      data: {
        remote: "true",
        behavior: @behavior || "selectable show_entries open_item feed_link renamable has_settings",
        settings_path: edit_subscription_path(@feed, app: true),
        dialog_id: helpers.dom_id(@feed),
        feed_id: @feed.id,
        sourceable_target: "source",
        action: "sourceable#selected",
        sourceable_payload_param: JSON.dump(@feed.sourceable.to_h),
        mark_read: {
          type: "feed",
          data: @feed.id,
          message: "Mark #{@feed.title} as read?"
        }.to_json
      }
    }
  end
end
