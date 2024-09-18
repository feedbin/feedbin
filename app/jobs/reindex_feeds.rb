class ReindexFeeds
  include Sidekiq::Worker

  def perform
    old_index = Search.client { _1.get_index_from_alias(alias_name: Feed.table_name) }
    new_index = "#{Feed.table_name}_#{Time.now.to_i}"
    Search.client(mirror: true) { _1.request(:put, new_index, json: $search[:config][:mappings][:feeds]) }
    reindex_data(new_index)
    Search.client(mirror: true) {
      _1.update_alias(alias_name: Feed.table_name, old_index: old_index, new_index: new_index)
    }
    Search.client(mirror: true) { _1.delete_index(old_index) }
  end

  private

  def reindex_data(new_index)
    feeds = Feed.order(subscriptions_count: :desc).where("subscriptions_count > 100")
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
    end
  end
end
