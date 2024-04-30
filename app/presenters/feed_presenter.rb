class FeedPresenter < BasePresenter
  presents :feed

  def feed_link(link: nil, behavior: nil, &block)
    args = [
      link || @template.feed_entries_path(feed),
      remote: true,
      class: "feed-link",
      data: {
        behavior: behavior || "selectable show_entries open_item feed_link renamable user_title has_settings",
        settings_path: @template.edit_subscription_path(feed, app: true),
        feed_id: feed.id,
        sourceable_target: "source",
        action: "sourceable#selected",
        sourceable_payload_param: feed.sourceable.to_h,
        mark_read: {
          type: "feed",
          data: feed.id,
          message: "Mark #{feed.title} as read?"
        }.to_json
      }
    ]
    @template.link_to *args do
      yield
    end
  end
end
