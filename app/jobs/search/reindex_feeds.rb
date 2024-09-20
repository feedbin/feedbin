module Search
  class ReindexFeeds
    include Sidekiq::Worker

    def perform
      Search.client(mirror: true) do |client|
        client.reindex(Feed.table_name, mappings: $search[:config][:mappings][:feeds]) do |new_index|
          reindex(new_index)
        end
      end
    end

    private

    def reindex(new_index)
      threshold = ENV.fetch("FEEDS_SEARCHABLE_THRESHOLD") { 1 }.to_i
      feeds = Feed.order(subscriptions_count: :desc).where("subscriptions_count > ?", threshold).reject { _1.crawl_error? }
      feeds = feeds.uniq { _1.self_url.nil? ? SecureRandom.hex : _1.self_url }
      feeds = feeds.uniq { "#{_1.title}#{_1.site_url&.delete_suffix("/")}" }

      feeds.each_slice(100) do |feeds|
        authors = Entry.last_n_per_feed(50, feeds.map(&:id)).each_with_object({}) do |entry, hash|
          hash[entry.feed_id] ||= Set.new
          hash[entry.feed_id].add(entry.author.to_s.downcase.to_plain_text)
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
  end
end