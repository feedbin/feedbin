module FeedCrawler
  class Receiver
    include Sidekiq::Worker
    sidekiq_options queue: :parse

    def perform(data)
      feed = Feed.find(data["feed"]["id"])
      if data["entries"].present?
        receive_entries(data["entries"], feed)
      end
      feed.update(data["feed"])
    end

    def receive_entries(items, feed)
      public_ids = items.map { |entry| entry["public_id"] }
      entries = Entry.where(public_id: public_ids).index_by(&:public_id)
      items.each do |item|
        entry = entries[item["public_id"]]
        update = item.delete("update")
        if entry
          EntryUpdate.create!(item, entry)
        else
          create_entry(item, feed)
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
    end

    def create_entry(item, feed)
      if alternate_exists?(item)
        Honeybadger.increment_counter("entry.alternate_exists")
      else
        feed.entries.create!(item)
        Honeybadger.increment_counter("entry.create")
        Sidekiq.logger.info "Creating entry=#{item["public_id"]}"
      end
    end

    def alternate_exists?(item)
      if item["data"] && item["data"]["public_id_alt"]
        FeedbinUtils.public_id_exists?(item["data"]["public_id_alt"])
      end
    end
  end
end