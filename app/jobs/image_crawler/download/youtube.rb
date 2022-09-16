# frozen_string_literal: true

module Crawler
  module Image
    class Download::Youtube < Download
      attr_reader :image_url

      def self.supported_urls
        [
          %r{.*?//www\.youtube-nocookie\.com/embed/(.*?)(\?|$)},
          %r{.*?//www\.youtube\.com/embed/(.*?)(\?|$)},
          %r{.*?//www\.youtube\.com/user/.*?#\w/\w/\w/\w/(.+)\b},
          %r{.*?//www\.youtube\.com/v/(.*?)(#|\?|$)},
          %r{.*?//www\.youtube\.com/watch\?v=(.*?)(&|#|$)},
          %r{.*?//youtube-nocookie\.com/embed/(.*?)(\?|$)},
          %r{.*?//youtube\.com/embed/(.*?)(\?|$)},
          %r{.*?//youtu\.be/(.+)}
        ]
      end

      def download
        ["maxresdefault", "hqdefault"].each do |option|
          @image_url = "https://i.ytimg.com/vi/#{provider_identifier}/#{option}.jpg"
          download_file(@image_url)
          break
        rescue Down::Error => exception
        end
      end
    end
  end
end