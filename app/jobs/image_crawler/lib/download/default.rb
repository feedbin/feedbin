module ImageCrawler
  class Download::Default < Download
    def self.recognize_url?(*args)
      true
    end

    def download
      download_file(image_url)
    rescue Feedkit::Error => exception
    end
  end
end