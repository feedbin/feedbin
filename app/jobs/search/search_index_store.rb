module Search
  class SearchIndexStore
    include Sidekiq::Worker
    sidekiq_options queue: :network_search

    def perform(klass, id, update = false)
      entry = Entry.find(id)
      document = entry.search_data
      index(entry, document)
      percolate(entry, document, update)
    rescue ActiveRecord::RecordNotFound
    end

    def index(entry, document)
      Search::Client.index(Entry.table_name, id: entry.id, document: SearchDataV2.new(entry).to_h)
    end

    def percolate(entry, document, update)
      result = Search::Client.percolate(entry.feed_id, document: document)
      ids = result.dig("hits", "hits")&.map {|hit| hit["_id"]&.to_i }
      if ids.present?
        ActionsPerform.perform_async(entry.id, ids, update)
      end
    end
  end
end