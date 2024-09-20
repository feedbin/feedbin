module Search
  class FeedMetadataFinder
    include Sidekiq::Worker
    sidekiq_options queue: :network_default

    def perform(feed_id)
      @feed = Feed.find(feed_id)
      return if Time.at(@feed.meta_crawled_at.to_i).after?(1.month.ago)
      response = HTTP
        .timeout(write: 5, connect: 5, read: 5)
        .use(:auto_inflate)
        .follow
        .headers(accept_encoding: "gzip")
        .get(@feed.site_url)

      document = Nokogiri::HTML5(response.to_s)
      @feed.update(meta_title: title(document), meta_description: description(document), meta_crawled_at: Time.now.to_i)
    end

    def title(document)
      document.css("head title").first&.text&.to_plain_text
    end

    def description(document)
      document.css("head meta[name=description]").first&.attribute("content")&.value&.to_plain_text
    end
  end
end