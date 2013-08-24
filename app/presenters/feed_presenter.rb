class FeedPresenter < BasePresenter
  
  presents :feed
  
  def feed_link(&block)
    @template.link_to @template.feed_entries_path(feed), remote: true, class: 'feed-link', data: { behavior: 'selectable reset_entry_position show_entries open_item' } do
      yield
    end
  end
  
  def favicon
    begin
      host = URI::parse(feed.site_url).host.parameterize
    rescue Exception => e
      host = 'none'
    end
    @template.content_tag :span, '', class: "favicon-wrap" do
      @template.content_tag(:span, '', class: "favicon-default") + 
      @template.content_tag(:span, '', class: "favicon favicon-#{host}")
    end
  end
  
  def feed_count
    @template.content_tag :span, feed.unread_count, class: count_classes
  end
  
  def classes
    @template.selected("feed_#{feed.id}")
  end
    
  private
  
  def show_count?
    feed.unread_count && feed.unread_count > 0
  end
  
  def count_classes
    classes = ['count']
    classes << 'hide' unless show_count?
    classes
  end
  
end