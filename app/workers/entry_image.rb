class EntryImage
  include Sidekiq::Worker
  sidekiq_options retry: false

  def perform(entry_id)
    Honeybadger.context(entry_id: entry_id)
    @entry = Entry.find(entry_id)
    @feed = @entry.feed
    find_image_url
  end

  def find_image_url
    if download = try_candidates(rss_candidates)
      save_image(download.to_h)
    elsif domains_match?
      check_for_meta_images
    end
  end

  def check_for_meta_images
    if page_checked?
      if image = cached_image
        save_image(image)
        Librato.increment 'entry_image.page_request.cache_hit'
      end
      Librato.increment 'entry_image.page_request.cached'
    else
      if download = try_candidates(page_candidates)
        save_image(download.to_h)
        set_cache(download.to_h.to_json)
      else
        set_cache("")
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

  def save_image(attributes)
    @entry.update_attributes(image: attributes)
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
    if check_page?
      Librato.increment 'entry_image.page_request'
      response = HTTParty.get(@entry.fully_qualified_url, timeout: 4)
      document = Nokogiri::HTML5(response.body)
      tags = document.search("meta[property='og:title'], meta[property='twitter:card'], meta[property='og:image'], meta[property='twitter:image']")
      if tags.any?
        $redis.set(feed_key, "true", ex: 24.hours.to_i, nx: true)
        candidates = tags.each_with_object([]) do |element, array|
          if ["twitter:image", "og:image"].include?(element["property"]) && element["content"].present?
            src = element["content"].strip
            candidate = ImageCandidate.new(src, "img")
            array.push(candidate)
          end
        end
      else
        $redis.set(feed_key, "", ex: 24.hours.to_i, nx: true)
      end
    else
      Librato.increment 'entry_image.page_request.skip'
    end
    candidates
  end

  def check_page?
    result = $redis.get(feed_key)
    result.nil? || result.present?
  end

  def feed_key
    "feed_meta_presence:#{@feed.id}"
  end

  def domains_match?
    host_one = URI(@entry.fully_qualified_url).host.split(".").last(2)
    host_two = URI(@feed.site_url).host.split(".").last(2)
    host_one == host_two
  end

  def try_candidate(candidate)
    found = false
    if candidate.valid?
      download = DownloadImage.new(candidate.original_url)
      if download.download
        found = download
      end
    end
    found
  end

  def cache_key
    "entry_image:#{Digest::SHA1.hexdigest(@entry.fully_qualified_url)}"
  end

  def cached_value
    @cached_value ||= $redis.get(cache_key)
  end

  def page_checked?
    cached_value
  end

  def cached_image
    if cached_value.present?
      JSON.parse(cached_value)
    else
      false
    end
  end

  def set_cache(value)
    $redis.set(cache_key, value, ex: 24.hours.to_i, nx: true)
  end

end
