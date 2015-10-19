class EntryImage
  include Sidekiq::Worker

  def perform(entry_id)
    @entry = Entry.find(entry_id)
    @feed = @entry.feed
    Honeybadger.context(entry_id: entry_id)
    find_image_url
  end

  def find_image_url
    candidates.each do |candidate|
      begin
        break if suitable_image_found?(candidate)
      rescue Exception => exception
        Librato.increment 'entry_image.exception'
        Honeybadger.notify(exception)
      end
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

  def suitable_image_found?(candidate)
    found = false
    if candidate.valid?
      url = candidate.url
      download = DownloadImage.new(url, @entry.id)
      if download.download
        @entry.image_url = url.to_s
        @entry.processed_image_url = download.image.url
        @entry.save
        found = true
        Librato.increment 'entry_image.create'
      end
    end
    found
  end

end
