module Crawler
  module Image
    class Download::Default < Download
      def self.recognize_url?(*args)
        true
      end

      def download
        download_file(image_url)
      rescue Down::Error => exception
      end
    end
  end
end