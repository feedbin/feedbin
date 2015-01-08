require 'RMagick'
class FaviconFetcher
  include Sidekiq::Worker
  sidekiq_options retry: false, queue: :favicon

  def perform(host)
    favicon = Favicon.where(host: host).first_or_initialize
    if !updated_recently?(favicon.updated_at)
      update_favicon(favicon)
    end
  rescue
    Librato.increment('favicon.failed')
  end

  def update_favicon(favicon)
    data = nil
    favicon_found = false

    favicon_url = find_favicon_link(favicon.host)
    if favicon_url
      data = download_favicon(favicon_url)
      favicon_found = true if data
    end

    if !favicon_found
      favicon_url = default_favicon_location(favicon.host)
      data = download_favicon(favicon_url)
    end

    if favicon.favicon != data
      favicon.favicon = data
      Librato.increment('favicon.updated')
    end

    favicon.save
  end

  def find_favicon_link(host)
    favicon_url = nil
    url = URI::HTTP.build(host: host)
    response = HTTParty.get(url, {timeout: 20})
    html = Nokogiri::HTML(response)
    favicon_links = html.search("//link[translate(@rel, 'ABCDEFGHIJKLMNOPQRSTUVWXYZ', 'abcdefghijklmnopqrstuvwxyz') = 'icon']/@href |" +
                                "//link[translate(@rel, 'ABCDEFGHIJKLMNOPQRSTUVWXYZ', 'abcdefghijklmnopqrstuvwxyz') = 'shortcut icon']/@href")

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

  def default_favicon_location(host)
    URI::HTTP.build(host: host, path: "/favicon.ico")
  end

  def download_favicon(url)
    response = HTTParty.get(url, timeout: 20, verify: false)
    base64_favicon(response.body)
  end

  def base64_favicon(data)
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
  end

  def remove_blank_images(favicons)
    favicons.reject do |favicon|
      favicon = favicon.scale(1, 1)
      pixel = favicon.pixel_color(0,0)
      favicon.to_color(pixel) == "none"
    end
  end

  def updated_recently?(date)
    if date
      date > 1.day.ago
    else
      false
    end
  end

end
