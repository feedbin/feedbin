class IframeEmbed::Youtube < IframeEmbed
  def self.supported_urls
    [
      %r{.*?//www\.youtube\.com/embed/(.*?)(\?|$)},
      %r{.*?//www\.youtube-nocookie\.com/embed/(.*?)(\?|$)},
      %r{.*?//youtube\.com/embed/(.*?)(\?|$)},
      %r{.*?//youtube-nocookie\.com/embed/(.*?)(\?|$)}
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
    channel && channel.data.dig("snippet", "title")
  end

  def duration
    if seconds = duration_in_seconds
      hours = seconds / (60 * 60)
      minutes = (seconds / 60) % 60
      seconds = seconds % 60

      parts = [minutes, seconds]
      parts.unshift(hours) unless hours == 0
      parts.map {|part| part.to_s.rjust(2, "0") }.join(":")
    end
  end

  def profile_image
    channel && channel.data.dig("snippet", "thumbnails", "medium", "url")
  end

  def cache_key
    video && "youtube_embed_#{video.updated_at.to_i}" || super
  end

  private

  def duration_in_seconds
    if duration = video && video.data.dig("contentDetails", "duration")
      match = duration.match %r{^P(?:|(?<weeks>\d*?)W)(?:|(?<days>\d*?)D)(?:|T(?:|(?<hours>\d*?)H)(?:|(?<min>\d*?)M)(?:|(?<sec>\d*?)S))$}
      weeks = (match[:weeks] || '0').to_i
      days = (match[:days] || '0').to_i
      hours = (match[:hours] || '0').to_i
      minutes = (match[:min] || '0').to_i
      seconds = (match[:sec]).to_i
      (((((weeks * 7) + days) * 24 + hours) * 60) + minutes) * 60 + seconds
    end
  end

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
