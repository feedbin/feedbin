module Api
  module V3
    # The entry object. Load entries with Entry.for_api_v3 so the image rows,
    # feed, and stored rendering come preloaded. The default shape carries feed_id;
    # expand names what to add (EXPANSIONS): the feed (feed is its serialized
    # hash, built once per feed) and the optional bodies under content. A
    # body not asked for is left out, one asked for that the entry does not
    # have is null.
    class EntrySerializer
      EXPANSIONS = %w[feed changes original_newsletter].freeze

      # membership is what a collection knows about the entry, serialized;
      # present only on collection reads. videos is the entry's list from
      # VideoLoader, which a page of entries loads once; left out, the entry
      # loads its own.
      def initialize(entry, feed: nil, expand: [], membership: nil, videos: nil)
        @entry = entry
        @feed = feed
        @expand = expand
        @membership = membership
        @videos = videos
      end

      def to_h
        hash = {
          object: "entry",
          id: @entry.id,
          feed_id: @entry.feed_id,
          kind: kind,
          title: kind == "micropost" ? nil : @entry.title&.to_plain_text.presence,
          author: author,
          summary: @entry.summary.presence,
          url: url,
          hostname: url && Addressable::URI.parse(url).host,
          published_at: @entry.published.utc.iso8601,
          received_at: @entry.created_at.utc.iso8601,
          revision: @entry.revision,
          edited_at: @entry.edited_at&.utc&.iso8601,
          images: {
            preview: image(@entry.preview_image_record),
            icon: image(icon_record)
          },
          link_preview: link_preview,
          attachments: attachments,
          videos: @videos || VideoLoader.call([@entry])[@entry.id],
          origin: origin,
          categories: Array(@entry.categories),
          extracted_content_url: @entry.fully_qualified_url && @entry.extracted_content_url,
          content: content,
          extracted: extracted
        }
        hash[:feed] = @feed if @expand.include?("feed")
        hash[:membership] = @membership if @membership
        hash
      end

      private

      def kind
        @kind ||= if @entry.feed.pages?
          "page"
        elsif @entry.feed.newsletter?
          "newsletter"
        elsif @entry.youtube?
          "video"
        elsif @entry.micropost? || @entry.tweet?
          "micropost"
        elsif @entry.data&.dig("enclosure_type").to_s.start_with?("audio/")
          "podcast"
        else
          "article"
        end
      end

      def author
        if kind == "newsletter" && (from = @entry.newsletter_from.presence)
          name, address = from.split(/[<>]/).map(&:strip)
          name.to_s.delete('"').presence || address
        else
          @entry.author.presence
        end
      end

      # A newsletter has no page of its own, so its url is Feedbin's copy.
      def url
        @url ||= (kind == "newsletter") ? @entry.newsletter_url : @entry.fully_qualified_url
      end

      # Episode art or a micropost author's avatar, then a YouTube channel's
      # picture, then a podcast's show art.
      def icon_record
        @entry.icon_image_record ||
          (@entry.channel_image_record if kind == "video") ||
          (@entry.feed.icon_image_record if kind == "podcast")
      end

      def image(record)
        record && ImageSerializer.new(record).to_h
      end

      def link_preview
        return nil unless kind == "micropost" && @entry.micropost&.link_preview?

        url = @entry.link_preview_url
        page = saved_page(url)
        {
          url: url,
          title: page&.title,
          hostname: Addressable::URI.parse(url).host,
          author: page&.author,
          image: image(@entry.link_image_record)
        }
      end

      def attachments
        enclosure = enclosure_attachment
        media = @entry.media.reject { _1.url == enclosure&.dig(:url) }.map do |item|
          AttachmentSerializer.new(url: item.url, mime_type: item.type).to_h
        end
        [enclosure, *media].compact
      end

      def enclosure_attachment
        data = @entry.data || {}
        url = @entry.rebase_url(data["enclosure_url"])
        return nil unless url && %w[http https].include?(Addressable::URI.parse(url).scheme&.downcase)

        AttachmentSerializer.new(
          url: url,
          mime_type: data["enclosure_type"],
          size_in_bytes: Integer(data["enclosure_length"], exception: false)&.then { _1.positive? ? _1 : nil },
          duration_in_seconds: @entry.audio_duration,
          chapters: chapters
        ).to_h
      rescue Addressable::URI::InvalidURIError
        nil
      end

      def chapters
        return nil unless @entry.chapters.respond_to?(:filter_map)
        list = @entry.chapters.filter_map do |chapter|
          title = chapter.safe_dig("tags", "title").presence
          start = Float(chapter.safe_dig("start_time"), exception: false)
          {start_in_seconds: start.floor, title: title.clean} if title && start
        end
        list.presence
      end

      def origin
        return nil unless @entry.provider_youtube?
        {provider: "youtube", id: @entry.provider_id, channel_id: @entry.provider_parent_id}
      end

      # The body object: html always, then each optional body in INCLUDES order.
      def content
        body = {html: content_html}
        body[:changes] = changes if @expand.include?("changes")
        body[:original_newsletter] = original_newsletter if @expand.include?("original_newsletter")
        body
      end

      def content_html
        @entry.rendering.api
      rescue => exception
        ErrorService.notify(exception, context: {entry_id: @entry.id})
        @entry.content
      end

      # The current body with the edit since the original marked as
      # insertions and deletions. Stored with the rendering; nil until an edit.
      def changes
        @entry.content_diff&.then { {html: _1.to_s} }
      end

      # The email as it was sent, lightly formatted: relaxed sanitization,
      # proxied images, and layout breakpoints pushed out of a reader pane's
      # reach. Rendered on request; nil for anything but a newsletter.
      def original_newsletter
        return nil unless kind == "newsletter"
        {html: ContentFormatter.newsletter_format(@entry.content).to_s}
      end

      # The article a micropost links to, as HarvestLinks saved it (it saves
      # the first link only), with the stored api rendering. nil otherwise.
      def extracted
        url, html = @entry.rendering.extracted_pages.first
        page = url && saved_page(url) or return nil
        {
          url: url,
          title: page.title,
          hostname: Addressable::URI.parse(url).host,
          author: page.author,
          content: {html: html}
        }
      rescue => exception
        ErrorService.notify(exception, context: {entry_id: @entry.id})
        nil
      end

      def saved_page(url)
        data = @entry.data&.dig("saved_pages", url)
        MercuryParser.new(nil, data: data) if data.respond_to?(:dig) && data["result"]
      end
    end
  end
end
