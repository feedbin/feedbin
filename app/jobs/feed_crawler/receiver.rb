module FeedCrawler
  class Receiver
    include Sidekiq::Worker
    sidekiq_options queue: :parse

    def perform(data)
      # The Sidekiq path round-trips this through JSON, so everything below
      # indexes with string keys. The import path calls perform in-process and
      # the filter's keys are symbols, which silently turned every lookup into
      # nil: no update was ever applied and the de-duplication guard was
      # bypassed.
      data = data.deep_stringify_keys
      feed = Feed.find(data["feed"]["id"])
      icon_urls = ImageCrawler::FeedIcon.source_urls(feed)
      created = 0
      if data["entries"].present?
        created = receive_entries(data["entries"], feed)
      end
      feed.update(data["feed"].except("feed_url", :feed_url))

      # The stored feed_icon row outranks options, so a new icon url (a
      # Mastodon account's new avatar) is fetched only if the crawl that
      # brings it asks. An unchanged url, or one that never landed, is not
      # asked for again.
      if ImageCrawler::FeedIcon.source_urls(feed) != icon_urls
        ImageCrawler::FeedIcon.perform_async(feed.id)
      end

      # Once per crawl with new posts, never per entry: the job dedupes the
      # feed's avatar urls in one pass. The marker is the parser's micropost
      # verdict for this very parse.
      if created > 0 && data["feed"]["custom_icon_format"] == "round"
        ImageCrawler::MicropostAvatar.perform_async(feed.id)
      end
    end

    # Returns the number of entries created.
    def receive_entries(items, feed)
      public_ids = items.map { |entry| entry["public_id"] }
      entries = Entry.where(public_id: public_ids).index_by(&:public_id)
      created = 0
      items.each do |item|
        entry = entries[item["public_id"]]
        update = item.delete("update")
        if entry
          EntryUpdate.create!(item, entry)
        elsif create_entry(item, feed)
          created += 1
        end
      rescue ActiveRecord::RecordNotUnique
        # Ignore
      rescue => exception
        unless exception.message =~ /Validation failed/i
          message = update ? "update" : "create"
          ErrorService.notify(
            error_class: "Receiver#" + message,
            error_message: "Entry #{message} failed",
            parameters: {feed_id: feed.id, item: item, exception: exception, backtrace: exception.backtrace}
          )
          Sidekiq.logger.info "Entry Error: feed=#{feed.id} exception=#{exception.inspect}"
        end
      end
      created
    end

    # Returns whether an entry was created.
    def create_entry(item, feed)
      if alternate_exists?(item)
        Librato.increment("entry.alternate_exists")
        false
      else
        feed.entries.create!(item)
        Librato.increment("entry.create")
        Sidekiq.logger.info "Creating entry=#{item["public_id"]}"
        true
      end
    end

    def alternate_exists?(item)
      if item["data"] && item["data"]["public_id_alt"]
        FeedbinUtils.public_id_exists?(item["data"]["public_id_alt"])
      end
    end
  end
end