module Search
  class ReindexFeeds
    include Sidekiq::Worker

    # How many feeds are held in memory at once.
    SLICE_SIZE = 100

    def perform
      Search.client(mirror: true) do |client|
        client.reindex(Search.index_name(Feed.table_name), mappings: $search[:config][:mappings][:feeds]) do |new_index|
          reindex(new_index)
        end
      end
    end

    private

    def reindex(new_index)
      feed_ids = searchable_feed_ids

      # The dedup below needs the whole set, but it only needs four columns to
      # do it. Resolving ids first and loading the full records a slice at a
      # time keeps the peak at one slice rather than the entire searchable
      # corpus -- every settings, options and crawl_data blob included -- inside
      # a long-lived worker.
      feed_ids.each_slice(SLICE_SIZE) do |ids|
        feeds = Feed.where(id: ids).to_a
        authors = Entry.last_n_per_feed(50, feeds.map(&:id)).pluck(:feed_id, :author).each_with_object({}) do |(feed_id, author), hash|
          hash[feed_id] ||= Set.new
          hash[feed_id].add(author.to_s.downcase.to_plain_text)
        end
        records = feeds.map do |feed|
          document = feed.search_data
          document[:author] = authors.fetch(feed.id) { [] }.to_a
          Search::BulkRecord.new(
            action: :index,
            index: new_index,
            id: feed.id,
            document: document
          )
        end
        Search.client(mirror: true) { _1.bulk(records) } unless records.empty?
        Sidekiq::Client.push_bulk(
          "args" => feeds.map {[_1.id]},
          "class" => FeedMetadataFinder
        )
      end
    end

    # Ordered by subscriptions_count like the original, so the dedup keeps the
    # most-subscribed feed of each duplicate group.
    def searchable_feed_ids
      threshold = ENV.fetch("FEEDS_SEARCHABLE_THRESHOLD") { 0 }.to_i

      rows = Feed.xml
        .where("subscriptions_count > ?", threshold)
        .where.not("feed_url LIKE ? OR feed_url LIKE ?", "%feedbin.com/starred%", "%feedbin.me/starred%")
        .order(subscriptions_count: :desc)
        .pluck(:id, :self_url, :title, :site_url, :crawl_data)

      rows = rows.reject { |_id, _self_url, _title, _site_url, crawl_data| crawl_error?(crawl_data) }
      rows.uniq! { |_id, self_url, _title, _site_url, _crawl_data| self_url.nil? ? SecureRandom.hex : self_url }
      rows.uniq! { |_id, _self_url, title, site_url, _crawl_data| "#{title}#{site_url&.delete_suffix("/")}" }
      rows.map(&:first)
    end

    def crawl_error?(crawl_data)
      crawl_data.respond_to?(:error_count) && crawl_data.error_count > 23
    end
  end
end
