class ParsedEntry

  ENTRY_ATTRIBUTES = %i(author content data entry_id public_id published source title url).freeze

  def initialize(entry, feed_url)
    @entry = entry
    @feed_url = feed_url
  end

  def author
    @author ||= begin
      value = nil
      if @entry.try(:author)
        value = @entry.author
      elsif @entry.try(:itunes_author)
        value = @entry.itunes_author
      end
      value
    end
  end

  def content
    @content ||= begin
      value = nil
      if @entry.try(:content)
        value = @entry.content
      elsif @entry.try(:summary)
        value = @entry.summary
      elsif @entry.try(:description)
        value = @entry.description
      elsif @entry.try(:media_description)
        value = @entry.media_description
      end
      value
    end
  end

  def data
    value = {}
    value[:enclosure_type]   = @entry.enclosure_type if @entry.try(:enclosure_type)
    value[:enclosure_url]    = @entry.enclosure_url if @entry.try(:enclosure_url)
    value[:enclosure_length] = @entry.enclosure_length if @entry.try(:enclosure_length)
    value[:itunes_duration]  = @entry.itunes_duration if @entry.try(:itunes_duration)
    value[:youtube_video_id] = @entry.youtube_video_id if @entry.try(:youtube_video_id)
    value[:media_width]      = @entry.media_width if @entry.try(:media_width)
    value[:media_height]     = @entry.media_height if @entry.try(:media_height)
    value
  end

  def entry_id
    @entry.entry_id ? @entry.entry_id.strip : nil
  end

  def public_id
    @public_id ||= begin
      id_string = @feed_url.dup
      if @entry.entry_id
        id_string << @entry.entry_id.dup
      else
        if @entry.url
          id_string << @entry.url.dup
        end
        if @entry.published
          id_string << @entry.published.iso8601
        end
        if @entry.title
          id_string << @entry.title.dup
        end
      end
      Digest::SHA1.hexdigest(id_string)
    end
  end

  def published
    @entry.published || Time.now
  end

  def source
    "Feedbin"
  end

  def title
    @entry.title ? @entry.title.strip : nil
  end

  def url
    @entry.url ? @entry.url.strip : nil
  end

  def to_entry
    @to_entry ||= begin
      ENTRY_ATTRIBUTES.each_with_object({}) do |attribute, hash|
        hash[attribute] = self.send(attribute)
      end
    end
  end

end
