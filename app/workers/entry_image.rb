class EntryImage
  include Sidekiq::Worker

  def perform(entry_id)
    Honeybadger.context(entry_id: entry_id)
    @entry = Entry.find(entry_id)
    @feed = @entry.feed
    find_image_url
  end

  def find_image_url

    download = nil

    candidates.each do |candidate|
      begin
        break if download = try_candidate(candidate)
      rescue Exception => exception
        Librato.increment 'entry_image.exception'
        Honeybadger.notify(exception)
      end
    end

    if download
      @entry.update_attributes(image: {
        original_url: download.url.to_s,
        processed_url: download.image.url.to_s,
        width: download.image.width,
        height: download.image.height,
      })
    end

  end

  def candidates
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
