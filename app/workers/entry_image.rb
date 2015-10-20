class EntryImage
  include Sidekiq::Worker

  def perform(entry_id)
    Honeybadger.context(entry_id: entry_id)
    @entry = Entry.find(entry_id)
    @feed = @entry.feed
    find_image_url
  end

  def find_image_url


    download = try_candidates(rss_candidates)
    if download
      save_image(download)
    else
      if download = try_candidates(page_candidates)
        save_image(download)
      end
    end

  end

  def try_candidates(candidates)
    download = nil
    candidates.each do |candidate|
      begin
        break if download = try_candidate(candidate)
      rescue Exception => exception
        Librato.increment 'entry_image.exception'
        Honeybadger.notify(exception)
      end
    end
    download
  end

  def save_image(download)
    @entry.update_attributes(image: {
      original_url: download.url.to_s,
      processed_url: download.image.url.to_s,
      width: download.image.width,
      height: download.image.height,
    })
    Librato.increment 'entry_image.create'
  end

  def rss_candidates
    document = Nokogiri::HTML5(@entry.content)
    elements = document.search("img, iframe")
    urls = elements.each_with_object([]) do |element, array|

      next if element["src"].blank?
      src = element["src"].strip
      next if src.start_with? "data"

      if src.start_with?('//')
        src = "http:#{src}"
      end

      if !src.start_with?('http')
        if src.start_with? '/'
          base = @feed.site_url
        else
          base = @entry.url || ""
        end
        begin
          src = URI.join(base, src).to_s
        rescue
        end
      end

      candidate = ImageCandidate.new(src, element.name)
      array.push(candidate)
    end
    urls.push(ImageCandidate.new(@entry.url, "iframe"))
  end

  def page_candidates
    candidates = []
    if domains_match?(@entry.fully_qualified_url, @feed.site_url)
      response = HTTParty.get(@entry.fully_qualified_url, timeout: 5)
      document = Nokogiri::HTML5(response.body)
      candidates = document.search("meta[property='og:image'], meta[property='twitter:image']").each_with_object([]) do |element, array|
        if element["content"].present?
          src = element["content"].strip
          candidate = ImageCandidate.new(src, "img")
          array.push(candidate)
        end
      end
    end
    candidates
  end

  def domains_match?(url_one, url_two)
    host_one = URI(url_one).host.split(".").last(2)
    host_two = URI(url_two).host.split(".").last(2)
    host_one == host_two
  end

  def try_candidate(candidate)
    found = false
    if candidate.valid?
      download = DownloadImage.new(candidate.original_url, @entry.id)
      if download.download
        found = download
      end
    end
    found
  end

end
