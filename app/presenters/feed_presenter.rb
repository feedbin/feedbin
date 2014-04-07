class FeedPresenter < BasePresenter

  presents :feed

  def feed_link(&block)
    @template.link_to @template.feed_entries_path(feed), remote: true, title: feed.title, class: 'feed-link', data: { behavior: 'selectable show_entries open_item feed_link', mark_read: {type: 'feed', data: feed.id, message: "Mark #{feed.title} as read?"}.to_json } do
      yield
    end
  end

  def feed_count
    @template.content_tag :span, feed.count, class: count_classes
  end

  def classes
    @template.selected("feed_#{feed.id}")
  end

  private

  def show_count?
    feed.count && feed.count > 0
  end

  def count_classes
    classes = ['count']
    classes << 'hide' unless show_count?
    classes
  end

end