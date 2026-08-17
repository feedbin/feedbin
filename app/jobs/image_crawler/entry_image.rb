module ImageCrawler
  class EntryImage
    include Sidekiq::Worker
    sidekiq_options retry: false

    IMAGE_SELECTORS = %w[
      meta[property="twitter:image"]
      meta[property="og:image"]
      img iframe video
    ]

    def perform(public_id, image = nil)
      if ENV["SKIP_IMAGES"].present?
        Rails.logger.info("SKIP_IMAGES is present, no images will be processed")
        return
      end

      @entry = Entry.find_by_public_id!(public_id)
      @image = image
      if @image
        receive
      elsif !@entry.processed_image?
        schedule
      end
    rescue ActiveRecord::RecordNotFound
    end

    def schedule
      if job = build_job
        Pipeline::Find.perform_async(job)
      end
    end

    def build_job
      image_urls = []
      meta_image_urls = []
      entry_url = nil
      preset_name = "primary"
      if @entry.tweet?
        tweets = []
        tweets.push(@entry.tweet.main_tweet)
        tweets.push(@entry.tweet.main_tweet.quoted_status) if @entry.tweet.main_tweet.quoted_status?
        tweet = tweets.find do |tweet|
          tweet.media?
        end
        image_urls = [tweet.media.first.media_url_https.to_s] unless tweet.nil?
      elsif @entry.youtube?
        image_urls = [@entry.fully_qualified_url]
        preset_name = "youtube"
      elsif @entry.micropost?
        image_urls, meta_image_urls = content_image_urls
        @entry.media.each do |media|
          image_urls.push(media.url) if media.type =~ /image/i
        end
      else
        entry_url = @entry.fully_qualified_url if same_domain?
        image_urls, meta_image_urls = content_image_urls
      end

      if image_urls.present? || entry_url.present?
        Image.new_with_attributes(
          id:              @entry.public_id,
          preset_name:     preset_name,
          image_urls:      image_urls,
          provider:        ::Image.providers[:entry_preview],
          provider_id:     @entry.id,
          entry_url:       entry_url,
          feed_id:         @entry.feed_id,
          page_url:        @entry.fully_qualified_url,
          meta_image_urls: meta_image_urls
        ).to_h
      end
    end

    def same_domain?
      entry_host = Addressable::URI.heuristic_parse(@entry.fully_qualified_url)&.host
      feed_host = @entry.feed.host
      entry_host == feed_host
    end

    def receive
      if @image["storage_path"]
        # Row-backed image: Upload/Dedupe already created the images row
        # before enqueueing this callback. The touch busts cached entry
        # views; metadata is not duplicated onto the entry.
        @entry.touch
      else
        @entry.update(image: @image)
      end
    end

    # find_image_urls tags each candidate with whether it came from a meta
    # tag. Split that into the full ordered candidate list and the meta-only
    # subset ReuseRules polices.
    def content_image_urls
      found = find_image_urls
      [found.map(&:first), found.select(&:last).map(&:first)]
    end

    def find_image_urls
      Nokogiri::HTML5(@entry.content)
        .css(IMAGE_SELECTORS.join(","))
        .sort_by do |element|
          IMAGE_SELECTORS.index { element.matches?(it) }
        end
        .each_with_object([]) do |element, array|
          source =      case element.name
          when "img"    then element["src"]
          when "iframe" then element["src"]
          when "video"  then element["poster"]
          when "meta"   then element["content"]
          end

          array.push([@entry.rebase_url(source), element.name == "meta"]) if source.present?
        end
    end

    def entry=(entry)
      @entry = entry
    end
  end
end