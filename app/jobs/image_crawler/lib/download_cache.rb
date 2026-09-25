module ImageCrawler
  # Remembers a candidate url that failed, so later crawls do not download
  # it again for a month. Only the url-addressed presets consult it: icons
  # always fetch (see Pipeline::Find#attempt_content_addressed).
  class DownloadCache
    def initialize(url, image)
      @url = url
      @image = image
    end

    def download?
      Cache.read(key)[:attempted] != true
    end

    def failed!
      Cache.write(key, {attempted: true}, options: {expires_in: 1.month})
    end

    private

    # The _v4_attempt tail is history. Changing it would forget every
    # failure on record.
    def key
      "image_download_#{@image.preset_name}_#{Digest::SHA1.hexdigest(@url)}_v4_attempt"
    end
  end
end
