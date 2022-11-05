module Search
  class SearchIndexRemove
    include Sidekiq::Worker

    def perform(ids)
      data = ids.map { |id|
        {delete: {_id: id}}
      }
      $search.each do |_, client|
        client.bulk(
          index: Entry.index_name,
          type: Entry.document_type,
          body: data
        )
      end
      
      records = ids.map do |id|
        Search::BulkRecord.new(
          action: :delete,
          index: Entry.table_name,
          id: id,
          document: nil
        )
      end
      Search::Client.bulk(records) unless records.empty?
    end
  end
end