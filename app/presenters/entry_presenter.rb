class EntryPresenter < BasePresenter

  presents :entry

  def entry_link(&block)
    options = {
      remote: true, class: 'wrap', data: {
        behavior: 'selectable open_item show_entry_content entry_info',
        mark_as_read_path: @template.mark_as_read_entry_path(entry),
        recently_read_path: @template.recently_read_entry_path(entry),
        entry_id: entry.id,
        entry_info: {id: entry.id, feed_id: entry.feed_id, published: entry.published.to_i}
      }
    }
    @template.link_to @template.entry_path(entry), options do
      yield
    end
  end

  def published_date
    if entry.published
      entry.published.to_s(:full_human)
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

  def parsed_date(date, format)
    begin
      date = Time.parse(date)
      date.to_s(format)
    rescue Exception
      nil
    end
  end

  def content(image_proxy_enabled)
    @content ||= ContentFormatter.format!(entry.content, entry, image_proxy_enabled)
  rescue HTML::Pipeline::Filter::InvalidDocumentException
    @template.content_tag(:p, '&ndash;&ndash;'.html_safe)
  end

  def has_content?
    entry.summary.respond_to?(:length) && entry.summary.length > 0
  end

  def title
    text = sanitized_title
    if text.blank?
      text = entry.summary.html_safe
    end
    if text.blank?
      text = '&ndash;&ndash;'.html_safe
    end
    text
  end

  def entry_view_title
    text = sanitized_title
    if text.blank?
      text = @template.content_tag(:span, '&ndash;&ndash;'.html_safe, title: "No title").html_safe
    end
    text
  end

  def sanitized_title
    @sanitized_title ||= @template.raw(@template.strip_tags(entry.title))
  end

  def author
    if entry.author
      clean_author = @template.strip_tags(entry.author)
      clean_author = "by " + @template.content_tag(:span, clean_author, class: "author")
    else
      clean_author = ''
    end
    clean_author.html_safe
  end

  def media_size
    begin
      size = Integer(entry.data['enclosure_length'])
      size = @template.number_to_human_size(size)
      size = "(#{size})"
    rescue Exception
      size = ''
    end
  end

  def media
    output = ''
    if entry.data && entry.data['enclosure_url'].present? && media_type.present?
      if media_type == :video
        output += @template.video_tag entry.data['enclosure_url'], preload: 'none'
      elsif media_type == :audio
        output += @template.audio_tag entry.data['enclosure_url'], preload: 'none'
      end
      output += @template.link_to "Download #{media_size}", entry.data['enclosure_url'], class: 'download-link'
    end
    output
  end

  def media_type
    if entry.data && entry.data['enclosure_type'] == 'video/mp4'
      :video
    elsif entry.data && entry.data['enclosure_type'] == 'audio/mpeg'
      :audio
    else
      nil
    end
  end

  def media_duration
    if entry.data['itunes_duration']
      entry.data['itunes_duration']
    else
      ''
    end
  end

  def feed_domain_matches?(comparison)
    begin
      uri = URI.parse(entry.feed.site_url)
      puts uri.host
      uri.host == comparison || uri.host == comparison.sub('www.', '')
    rescue Exception
      false
    end
  end

  def has_media?
    !media_type.nil? || content.include?('<iframe')
  end

end