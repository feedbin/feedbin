class ImageCandidate
  YOUTUBE_URLS = [%r(https?://youtu\.be/(.+)), %r(https?://www\.youtube\.com/watch\?v=(.*?)(&|#|$)), %r(https?://www\.youtube\.com/embed/(.*?)(\?|$)), %r(https?://www\.youtube\.com/v/(.*?)(#|\?|$)), %r(https?://www\.youtube\.com/user/.*?#\w/\w/\w/\w/(.+)\b)]
  VIMEO_URL = %r(https?://player\.vimeo\.com/video/(.*?)(#|\?|$))
  IGNORE_EXTENSIONS = [".gif", ".png", ".webp"]

  def initialize(src, element)
    @src = src
    @element = element
    @valid = true
    @url = nil

    if image?
      @check_for_redirect = true
      @url = image_candidate
    elsif iframe?
      @url = iframe_candidate
    else
      @valid = false
    end
  end

  def valid?
    return @valid
  end

  def url
    if @url.respond_to?(:call)
      @url = @url.call
    end

    if @check_for_redirect
      last_effective_uri(@url)
    else
      URI(@url)
    end
  end

  private

  def image?
    @element == "img"
  end

  def iframe?
    @element == "iframe"
  end

  def image_candidate
    if IGNORE_EXTENSIONS.find { |extension| @src.include?(extension) }
      @valid = false
    end
    @src
  end

  def iframe_candidate
    uri = nil
    if YOUTUBE_URLS.find { |format| @src =~ format } && $1
      uri = youtube_uri($1)
    elsif @src =~ VIMEO_URL && $1
      uri = vimeo_uri($1)
    else
      @valid = false
    end
    uri
  end

  def vimeo_uri(id)
    lambda do
      uri = nil
      query = {url: "https://vimeo.com/#{id}"}.to_query
      options = {
        scheme: "https",
        host: "vimeo.com",
        path: "/api/oembed.json",
        query: query
      }
      uri = URI::HTTP.build(options)
      response = HTTParty.get(uri, timeout: 5)

      if response.code == 200
        puts response.inspect
        uri = response.parsed_response["thumbnail_url"]
        uri = uri.gsub(/_\d+.jpg/, ".jpg")
      else
        uri = nil
        @valid = false
      end

      uri
    end
  end

  def youtube_uri(id)
    "http://img.youtube.com/vi/#{id}/maxresdefault.jpg"
  end

  def last_effective_uri(uri)
    response = HTTParty.head(uri, verify: false)
    response.request.last_uri
  end

end