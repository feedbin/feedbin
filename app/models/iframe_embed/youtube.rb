class IframeEmbed::Youtube < IframeEmbed
  def self.supported_urls
    [
      %r{.*?//www\.youtube-nocookie\.com/embed/(.*?)(\?|$)},
      %r{.*?//www\.youtube\.com/embed/(.*?)(\?|$)},
      %r{.*?//www\.youtube\.com/user/.*?#\w/\w/\w/\w/(.+)\b},
      %r{.*?//www\.youtube\.com/v/(.*?)(#|\?|$)},
      %r{.*?//www\.youtube\.com/watch\?v=(.*?)(&|#|$)},
      %r{.*?//m\.youtube\.com/watch\?v=(.*?)(&|#|$)},
      %r{.*?//youtube-nocookie\.com/embed/(.*?)(\?|$)},
      %r{.*?//youtube\.com/embed/(.*?)(\?|$)},
      %r{.*?//youtu\.be/(.*?)(\?|$)}
    ]
  end

  def oembed_url
    @oembed_url ||= "https://www.youtube.com/oembed"
  end

  def image_url
    url = data["thumbnail_url"].sub "hqdefault", "maxresdefault"
    status = Rails.cache.fetch("youtube_thumb_status:#{Digest::SHA1.hexdigest(url)}") {
      HTTP.head(url).status
    }
    if status == 200
      url
    else
      data["thumbnail_url"]
    end
  end

  def canonical_url
    "https://youtu.be/#{provider_id}"
  end

  def provider_id
    embed_url_data[1]
  end

  def iframe_params
    {
      "autoplay" => "1",
      "rel" => "0",
      "showinfo" => "0"
    }
  end

  def oembed_params
    {url: canonical_url, format: "json"}
  end

  def channel_name
    channel && channel.data.safe_dig("snippet", "title")
  end

  def duration
    return unless seconds = video && video.duration_in_seconds

    hours = seconds / (60 * 60)
    minutes = (seconds / 60) % 60
    seconds = seconds % 60

    parts = [minutes, seconds]
    parts.unshift(hours) unless hours == 0
    parts.map {|part| part.to_s.rjust(2, "0") }.join(":")
  end

  def profile_image
    channel && channel.data.safe_dig("snippet", "thumbnails", "medium", "url")
  end

  def cache_key
    video && "youtube_embed_#{video.updated_at.to_i}" || super
  end

  private

  def channel
    if @channel.nil?
      @channel = video && video&.channel || false
    end
    @channel
  end

  def video
    if @video.nil?
      @video = Embed.youtube_video.find_by_provider_id(provider_id) || false
    end
    @video
  end
end
