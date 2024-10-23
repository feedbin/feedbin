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
      threshold = ENV.fetch("FEEDS_SEARCHABLE_THRESHOLD") { 0 }.to_i
      feeds = Feed.xml.order(subscriptions_count: :desc).where("subscriptions_count > ?", threshold).reject { _1.crawl_error? }
      feeds.uniq! { _1.self_url.nil? ? SecureRandom.hex : _1.self_url }
      feeds.uniq! { "#{_1.title}#{_1.site_url&.delete_suffix("/")}" }
      feeds.reject! { _1.feed_url.include?("feedbin.com/starred") ||  _1.feed_url.include?("feedbin.me/starred")}

      feeds.each_slice(100) do |feeds|
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
  end
end
