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
        body: data,
      )
    end
  end
end
