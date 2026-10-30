module Api
  module V3
    # The entry object, with every field and its feed embedded. Load entries
    # with Entry.with_list_associations so the image rows and feed come
    # preloaded. feed is the feed's serialized hash, built once per feed.
    class EntrySerializer
      WORDS_PER_MINUTE = 200

      def initialize(entry, feed:)
        @entry = entry
        @feed = feed
      end

      def to_h
        {
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
          reading: reading,
          images: {
            preview: image(@entry.preview_image_record),
            icon: image(icon_record)
          },
          link_preview: link_preview,
          attachments: attachments,
          origin: origin,
          categories: Array(@entry.categories),
          urls: {
            app: Rails.application.routes.url_helpers.entry_url(@entry, **Rails.application.config.action_mailer.default_url_options),
            extracted_content: @entry.fully_qualified_url && @entry.extracted_content_url
          },
          content: {html: content_html},
          original: original,
          diff: @entry.content_diff&.then { {html: _1.to_s} },
          extracted: extracted,
          feed: @feed
        }
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

      def reading
        words = @entry.content.to_s.to_plain_text.split.size
        return nil if words.zero?
        {word_count: words, minutes: (words / WORDS_PER_MINUTE.to_f).ceil}
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

      def content_html
        ContentFormatter.api_format(@entry.content, @entry)
      rescue => exception
        ErrorService.notify(exception, context: {entry_id: @entry.id})
        @entry.content
      end

      # Only the content from before the first significant edit is kept.
      def original
        content = @entry.original_content
        content && {content: content}
      end

      # A micropost's linked articles, as HarvestLinks saved them.
      def extracted
        pages = @entry.data&.dig("saved_pages")
        return [] unless pages.respond_to?(:filter_map)

        pages.filter_map do |url, data|
          next unless data.respond_to?(:dig) && data["result"]
          page = MercuryParser.new(nil, data: data)
          {
            url: url,
            title: page.title,
            hostname: Addressable::URI.parse(url).host,
            author: page.author,
            content: ContentFormatter.api_format(page.content, nil)
          }
        rescue
          nil
        end
      end

      def saved_page(url)
        data = @entry.data&.dig("saved_pages", url)
        MercuryParser.new(nil, data: data) if data.respond_to?(:dig) && data["result"]
      end
    end
  end
end
