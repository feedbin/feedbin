class ParsedEntry

  attr_accessor :entry
  
  def initialize(entry:, feed:, base_feed_url: nil)
    @entry = {
      content: get_content(entry)
      author: entry.author ? entry.author.strip : nil
      content: content ? content.strip : nil
      title: entry.title ? entry.title.strip : nil
      url: entry.url ? entry.url.strip : nil
      published: entry.published ? entry.published : nil
      updated: entry.updated ? entry.updated : nil
      entry_id: entry.entry_id ? entry.entry_id.strip : nil
      public_id: build_public_id(entry, feed, base_feed_url)
      data: get_data(entry)
    }
  end

  private

  def get_content(entry)
    content = nil
    if entry.try(:content)
      content = entry.content
    elsif entry.try(:summary)
      content = entry.summary
    elsif entry.try(:description)
      content = entry.description
    end
    content
  end

  def get_data(entry)
    data = {}
    if entry.try(:enclosure_type) && entry.try(:enclosure_url)
      data[:enclosure_type] = entry.enclosure_type ? entry.enclosure_type : nil
      data[:enclosure_url] = entry.enclosure_url ? entry.enclosure_url : nil
      data[:enclosure_length] = entry.enclosure_length ? entry.enclosure_length : nil
      data[:itunes_duration] = entry.itunes_duration ? entry.itunes_duration : nil
    end
    data
  end

  # This is the id strategy
  # All values are stripped
  # feed url + id
  # feed url + link + utc iso 8601 date
  # feed url + link + title

  # WARNING: changes to this will break how entries are identified
  # This can only be changed with backwards compatibility in mind
  def build_public_id(entry, feed, base_feed_url = nil)
    if base_feed_url
      id_string = base_feed_url.dup
    else
      id_string = feed.feed_url.dup
    end

    if entry.entry_id
      id_string << entry.entry_id.dup
    else
      if entry.url
        id_string << entry.url.dup
      end
      if entry.published
        id_string << entry.published.iso8601
      end
      if entry.title
        id_string << entry.title.dup
      end
    end
    Digest::SHA1.hexdigest(id_string)
  end

end
