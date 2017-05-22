require 'socket'

class ParsedXMLEntry < ParsedEntry

  def entry_id
    @entry.entry_id ? @entry.entry_id.strip : nil
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

  def title
    @entry.title ? @entry.title.strip : nil
  end

  def url
    @entry.url ? @entry.url.strip : nil
  end

end
