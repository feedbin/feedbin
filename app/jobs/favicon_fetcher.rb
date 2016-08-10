require 'rmagick'
class FaviconFetcher
  include Sidekiq::Worker
  sidekiq_options retry: false

  def perform(host, force = false)
    @favicon = Favicon.where(host: host).first_or_initialize
    @force = force
    update if should_update?
  rescue
    Librato.increment('favicon.failed')
  end

  def update
    data = nil
    favicon_found = false
    response = nil

    favicon_url = find_favicon_link
    if favicon_url
      response = download_favicon(favicon_url)
      favicon_found = true if !response.to_s.empty?
    end

    if !favicon_found
      favicon_url = default_favicon_location
      response = download_favicon(favicon_url)
    end

    if response
      data = response.to_s
      favicon_hash = Digest::SHA1.hexdigest(data)
      if data.present? && @favicon.data["favicon_hash"] != favicon_hash
        image = format_favicon(response.to_s)
        @favicon.favicon = image if image
        @favicon.data = get_data(response, favicon_hash)
        Librato.increment('favicon.updated')
      end
      Librato.increment('favicon.status', source: response.code)
    end

    @favicon.save
  end

  def get_data(response, favicon_hash)
    data = {favicon_hash: favicon_hash}
    if response
      data = data.merge!(response.headers.to_h.extract!("Last-Modified", "Etag"))
    end
    data
  end

  def find_favicon_link
    favicon_url = nil
    url = URI::HTTP.build(host: @favicon.host)
    response = HTTP
      .timeout(:global, write: 5, connect: 5, read: 5)
      .follow()
      .get(url)
      .to_s
    html = Nokogiri::HTML(response)
    favicon_links = html.search(xpath)
    if favicon_links.present?
      favicon_url = favicon_links.last.to_s
      favicon_url = URI.parse(favicon_url)
      favicon_url.scheme = 'http'
      if !favicon_url.host
        favicon_url = URI::HTTP.build(scheme: 'http', host: host)
        favicon_url = favicon_url.merge(favicon_links.last.to_s)
      end
    end
    favicon_url
  rescue
    nil
  end

  def default_favicon_location
    URI::HTTP.build(host: @favicon.host, path: "/favicon.ico")
  end

  def download_favicon(url)
    response = HTTP
      .timeout(:global, write: 5, connect: 5, read: 5)
      .follow()
      .headers(request_headers)
      .get(url)
  end

  def request_headers
    headers = {user_agent: "Mozilla/5.0"}
    if !@force
      conditional_headers = ConditionalHTTP.new(@favicon.data["Etag"], @favicon.data["Last-Modified"])
      headers = headers.merge(conditional_headers.to_h)
    end
    headers
  end

  def format_favicon(data)
    begin
      favicons = Magick::Image.from_blob(data)
    rescue Magick::ImageMagickError
      favicons = Magick::Image.from_blob(data) { |image| image.format = 'ico' }
    end
    favicon = remove_blank_images(favicons).last
    if favicon.columns > 32
      favicon = favicon.resize_to_fit(32, 32)
    end
    blob = favicon.to_blob { |image| image.format = 'png' }
    Base64.encode64(blob).gsub("\n", '')
  rescue
    nil
  ensure
    favicon && favicon.destroy!
    favicons && favicons.map(&:destroy!)
  end

  def remove_blank_images(favicons)
    favicons.reject do |favicon|
      favicon = favicon.scale(1, 1)
      pixel = favicon.pixel_color(0,0)
      favicon.to_color(pixel) == "none"
    end
  end

  def should_update?
    if @force
      true
    else
      !updated_recently?
    end
    true
  end

  def updated_recently?
    if @favicon.updated_at
      @favicon.updated_at > 1.day.ago
    else
      false
    end
  end

  def xpath
    icon_names = ["icon", "shortcut icon"]
    icon_names = icon_names.map do |icon_name|
      "//link[not(@mask) and translate(@rel, 'ABCDEFGHIJKLMNOPQRSTUVWXYZ', 'abcdefghijklmnopqrstuvwxyz') = '#{icon_name}']/@href"
    end
    icon_names.join(" | ")
  end

end
