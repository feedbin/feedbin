class ImageFallback

  attr_accessor :document

  def initialize(document)
    @document = document
  end

  def add_fallbacks
    document.search("img").each do |image|
      src = image["data-canonical-src"]
      next unless src.respond_to?(:start_with?) && src.start_with?("http")
      image["onerror"] = "this.onerror=null;this.src='%s';" % fallback_url(src.strip)
    end
    document
  end

  def fallback_url(url)
    key = Download.new(url).path
    S3_POOL.with do |connection|
      connection.directories.new(key: ENV["AWS_S3_BUCKET_ARCHIVE"]).files.new(key: key).url(24.hours.from_now)
    end
  end

end