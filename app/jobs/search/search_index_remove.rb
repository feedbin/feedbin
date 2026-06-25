module Search
  class SearchIndexRemove
    include Sidekiq::Worker

    def perform(ids)
      records = ids.map do |id|
        Search::BulkRecord.new(
          action: :delete,
          index: Search.index_name(Entry.table_name),
          id: id,
          document: nil
        )
      end
      Search.client(mirror: true) { _1.bulk(records) }  unless records.empty?
    end
  end
end