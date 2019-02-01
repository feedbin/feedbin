require "rmagick"

class FaviconFetcher
  include Sidekiq::Worker
  sidekiq_options retry: false

  def perform(host, force = false)
    @favicon = Favicon.unscoped.where(host: host).first_or_initialize
    @force = force
    update if should_update?
  rescue
    Librato.increment("favicon.failed")
  end

  def update
    data = nil
    favicon_found = false
    response = nil

    favicon_url = find_favicon_link
    if favicon_url
      response = download_favicon(favicon_url)
      favicon_found = true unless response.to_s.empty?
    end

    unless favicon_found
      favicon_url = default_favicon_location
      response = download_favicon(favicon_url)
    end

    if response
      processor = FaviconProcessor.new(response.to_s, @favicon.host)
      if processor.valid? && @favicon.data["favicon_hash"] != processor.favicon_hash
        @favicon.favicon = processor.encoded_favicon if processor.encoded_favicon
        @favicon.url = processor.favicon_url if processor.favicon_url
        @favicon.data = get_data(response, processor.favicon_hash)
        Librato.increment("favicon.updated")
      end
      Librato.increment("favicon.status", source: response.code)
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
    response = HTTP.
      timeout(:global, write: 5, connect: 5, read: 5).
      follow.
      get(url).
      to_s
    html = Nokogiri::HTML(response)
    favicon_links = html.search(xpath)
    if favicon_links.present?
      favicon_url = favicon_links.last.to_s
      favicon_url = URI.parse(favicon_url)
      favicon_url.scheme = "http"
      unless favicon_url.host
        favicon_url = URI::HTTP.build(scheme: "http", host: @favicon.host)
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
    response = HTTP.
      timeout(:global, write: 5, connect: 5, read: 5).
      follow.
      headers(request_headers).
      get(url)
  end

  def request_headers
    headers = {user_agent: "Mozilla/5.0"}
    unless @force
      conditional_headers = ConditionalHTTP.new(@favicon.data["Etag"], @favicon.data["Last-Modified"])
      headers = headers.merge(conditional_headers.to_h)
    end
    headers
  end

  def should_update?
    if @force
      true
    else
      !updated_recently?
    end
  end

  def updated_recently?
    if @favicon.updated_at
      @favicon.updated_at > 1.hour.ago
    else
      false
    end
  end

  def xpath
    icon_names = ["icon", "shortcut icon"]
    icon_names = icon_names.map { |icon_name|
      "//link[not(@mask) and translate(@rel, 'ABCDEFGHIJKLMNOPQRSTUVWXYZ', 'abcdefghijklmnopqrstuvwxyz') = '#{icon_name}']/@href"
    }
    icon_names.join(" | ")
  end
end
