module Search
  class FeedMetadataFinder
    include Sidekiq::Worker

    sidekiq_options queue: :network_default, retry: false

    def perform(feed_id)
      @feed = Feed.find(feed_id)
      return if Time.at(@feed.meta_crawled_at.to_i).after?(1.month.ago)
      url = @feed.site_url
      return @feed.update(meta_crawled_at: Time.now.to_i) if url.blank?

      response = Feedkit::Request.download(url, block_ssrf: true, timeout: {connect: 5, write: 5, read: 5})
      return @feed.update(meta_crawled_at: Time.now.to_i) if response.status == 304

      document = parse_document(response)
      @feed.update(meta_title: title(document), meta_description: description(document), meta_crawled_at: Time.now.to_i)
    rescue Feedkit::Error, Encoding::InvalidByteSequenceError, Encoding::UndefinedConversionError
      @feed.update(meta_crawled_at: Time.now.to_i)
    end

    def parse_document(response)
      body = response.body
      Nokogiri::HTML5(body)
    rescue Encoding::InvalidByteSequenceError, Encoding::UndefinedConversionError
      encoding = response.encoding || Feedkit::DetectEncoding.detect(body).encoding || Encoding::UTF_8
      body = body.dup.force_encoding(encoding)
      Nokogiri::HTML5(body.encode(Encoding::UTF_8, invalid: :replace, undef: :replace))
    end

    def title(document)
      document.css("head title").first&.text&.to_plain_text
    end

    def description(document)
      document.css("head meta[name=description]").first&.attribute("content")&.value&.to_plain_text
    end
  end
end
