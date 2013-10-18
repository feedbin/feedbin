class EntryPresenter < BasePresenter

  presents :entry

  def read_state
    'read' if entry.read
  end

  def starred_state
    'starred' if entry.starred
  end

  def classes
    classes = []
    classes << read_state if read_state
    classes << starred_state if starred_state
    classes.join ' '
  end

  def entry_link(&block)
    @template.link_to @template.entry_path(entry), {
      remote: true, class: 'wrap', data: {
        behavior: 'selectable reset_entry_content_position open_item show_entry_content',
        mark_as_read_path: @template.mark_as_read_entry_path(entry)
      }
    } do
      yield
    end
  end

  def published_date
    if entry.published
      entry.published.to_s(:feed)
    else
      ''
    end
  end

  def datetime
    if entry.published
      entry.published.to_s(:datetime)
    else
      ''
    end
  end

  def content
    ContentFormatter.format!(entry.content, entry)
  rescue HTML::Pipeline::Filter::InvalidDocumentException
    '(no content)'
  end

  def has_content?
    entry.summary.respond_to?(:length) && entry.summary.length > 0
  end

  def title
    @template.raw(@template.strip_tags(entry.title)) || '(No title)'
  end

  def author
    @template.strip_tags(entry.author)
  end

end