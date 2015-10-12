class EntryImage
  include Sidekiq::Worker

  YOUTUBE_URLS = [
    %r(https?://youtu\.be/(.+)),
    %r(https?://www\.youtube\.com/watch\?v=(.*?)(&|#|$)),
    %r(https?://www\.youtube\.com/embed/(.*?)(\?|$)),
    %r(https?://www\.youtube\.com/v/(.*?)(#|\?|$)),
    %r(https?://www\.youtube\.com/user/.*?#\w/\w/\w/\w/(.+)\b)
  ]

  VIMEO_URL = %r(https?://player\.vimeo\.com/video/(.*?)(#|\?|$))

  def perform(entry_id)
    @entry = Entry.find(entry_id)
    @feed = @entry.feed
    urls = candidates
    url = urls.first
    if url.respond_to?(:call)
      url = url.call
    end
    @entry.image_url = url
    @entry.save
  end

  def candidates
    document = Nokogiri::HTML5(@entry.content)
    elements = document.search("img, iframe")
    elements.each_with_object([]) do |element, array|
      candidate = nil

      next if element["src"].blank?
      src = element["src"].strip
      next if src.start_with? "data"

      if element.name == "img"
        candidate = image_candidate(src, @feed.site_url, @entry.url || "")
      elsif element.name == "iframe"
        candidate = iframe_candidate(src)
      end

      array.push(candidate) if candidate
    end
  end

  def image_candidate(src, base_url, subpage_url)
    url = src
    if !src.start_with?('http')
      if src.start_with? '/'
        base = base_url
      else
        base = subpage_url
      end
      begin
        url = URI.join(base, src).to_s
      rescue
      end
    end
    url
  end

  def iframe_candidate(src)
    url = nil
    if YOUTUBE_URLS.find { |format| src =~ format } && $1
      url = youtube_url($1)
    elsif src =~ VIMEO_URL && $1
      url = vimeo_url($1)
    end
    return url
  end

  def vimeo_url(id)
    lambda do
      url = nil
      query = {url: "https://vimeo.com/#{id}"}.to_query
      options = {
        scheme: "https",
        host: "vimeo.com",
        path: "/api/oembed.json",
        query: query
      }
      url = URI::HTTP.build(options)
      puts url.inspect
      response = HTTParty.get(url, timeout: 5)

      if response.code == 200
        url = response.parsed_response["thumbnail_url"]
        url = url.gsub(/_\d+.jpg/, ".jpg")
      end

      url
    end
  end

  def youtube_url(id)
    "http://img.youtube.com/vi/#{id}/maxresdefault.jpg"
  end

end
