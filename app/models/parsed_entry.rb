require 'socket'

class ParsedEntry

  ENTRY_ATTRIBUTES = %i(author content data entry_id public_id published source title url).freeze

  def initialize(entry, feed_url)
    @entry = entry
    @feed_url = feed_url
  end

  def to_entry
    @to_entry ||= begin
      ENTRY_ATTRIBUTES.each_with_object({}) do |attribute, hash|
        hash[attribute] = self.send(attribute)
      end
    end
  end

  def build_id(base_entry_id)
    parts = []
    parts.push(@feed_url)
    parts.push(base_entry_id)
    if !entry_id
      parts.push(url)
      parts.push(published.iso8601) if published.respond_to?(:iso8601)
      parts.push(title)
    end
    Digest::SHA1.hexdigest(parts.compact.join)
  end

  def public_id
    @public_id ||= build_id(entry_id)
  end

  def public_id_alt
    @public_id_alt ||= begin
      if entry_id_alt
        build_id(entry_id_alt)
      end
    end
  end

  def entry_id
    @entry.entry_id ? @entry.entry_id.strip : nil
  end

  def entry_id_alt
    @entry_id_alt ||= begin
      if entry_id
        if entry_id.include?("http:")
          entry_id.sub("http:", "https:")
        elsif entry_id.include?("https:")
          entry_id.sub("https:", "http:")
        end
      end
    end
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
    value[:public_id_alt]    = public_id_alt if public_id_alt
    value
  end

  def published
    @entry.published
  end

  def source
    Socket.gethostname
  end

  def title
    @entry.title ? @entry.title.strip : nil
  end

  def url
    @entry.url ? @entry.url.strip : nil
  end

end
