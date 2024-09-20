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
      feeds = Feed.order(subscriptions_count: :desc).where("subscriptions_count > 50").reject { _1.crawl_error? }
      feeds = feeds.uniq { _1.self_url.nil? ? SecureRandom.hex : _1.self_url }
      feeds = feeds.uniq { "#{_1.title}#{_1.site_url&.delete_suffix("/")}" }

      feeds.each_slice(1_000) do |feeds|
        records = feeds.map do |feed|
          Search::BulkRecord.new(
            action: :index,
            index: new_index,
            id: feed.id,
            document: feed.search_data
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